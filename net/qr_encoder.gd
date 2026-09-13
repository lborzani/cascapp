class_name QrEncoder
extends RefCounted

## Minimal QR Code encoder written in pure GDScript so the pairing screen has no
## native dependency. Byte mode, error correction level M, versions 1 to 9
## (up to 182 bytes) — far more than the ~50 byte pairing payload needs.
##
## `encode()` returns {"size": int, "modules": PackedByteArray} where modules is
## a row-major size*size grid of 0 (light) and 1 (dark), without the quiet zone.

const MODE_BYTE := 0b0100
## ECC level M, as it appears in the format information bits.
const ECC_LEVEL_BITS := 0b00
const PAD_BYTES := [0xEC, 0x11]

## Per version: total data codewords, ECC codewords per block, then the block
## layout as [count, data_size] groups, and the alignment pattern centres.
const VERSION_TABLE := {
	1: {"data": 16, "ecc": 10, "blocks": [[1, 16]], "align": []},
	2: {"data": 28, "ecc": 16, "blocks": [[1, 28]], "align": [6, 18]},
	3: {"data": 44, "ecc": 26, "blocks": [[1, 44]], "align": [6, 22]},
	4: {"data": 64, "ecc": 18, "blocks": [[2, 32]], "align": [6, 26]},
	5: {"data": 86, "ecc": 24, "blocks": [[2, 43]], "align": [6, 30]},
	6: {"data": 108, "ecc": 16, "blocks": [[4, 27]], "align": [6, 34]},
	7: {"data": 124, "ecc": 18, "blocks": [[4, 31]], "align": [6, 22, 38]},
	8: {"data": 154, "ecc": 22, "blocks": [[2, 38], [2, 39]], "align": [6, 24, 42]},
	9: {"data": 182, "ecc": 22, "blocks": [[3, 36], [2, 37]], "align": [6, 26, 46]},
}
## Unused bits appended after the interleaved codewords, per version.
const REMAINDER_BITS := {1: 0, 2: 7, 3: 7, 4: 7, 5: 7, 6: 7, 7: 0, 8: 0, 9: 0}

const MAX_VERSION := 9

static var _exp_table := PackedInt32Array()
static var _log_table := PackedInt32Array()


static func encode(text: String) -> Dictionary:
	var data := text.to_utf8_buffer()
	var version := _pick_version(data.size())
	assert(version > 0, "payload too large for a version 1-9 QR code")

	var codewords := _build_codewords(data, version)
	var size := 17 + 4 * version
	var reserved := PackedByteArray()
	reserved.resize(size * size)
	reserved.fill(0)
	var modules := PackedByteArray()
	modules.resize(size * size)
	modules.fill(0)

	_draw_function_patterns(modules, reserved, size, version)
	_draw_codewords(modules, reserved, size, codewords, version)

	var best_mask := 0
	var best_penalty := -1
	var best_modules := modules
	for mask in 8:
		var candidate := modules.duplicate()
		_apply_mask(candidate, reserved, size, mask)
		_draw_format_bits(candidate, size, mask)
		var penalty := _penalty(candidate, size)
		if best_penalty < 0 or penalty < best_penalty:
			best_penalty = penalty
			best_mask = mask
			best_modules = candidate
	return {"size": size, "modules": best_modules, "mask": best_mask, "version": version}


static func _pick_version(byte_count: int) -> int:
	for version in range(1, MAX_VERSION + 1):
		# 4 bits mode + 8 bits length + payload.
		if int(VERSION_TABLE[version]["data"]) * 8 >= 12 + byte_count * 8:
			return version
	return -1


# --- data encoding -----------------------------------------------------------


static func _build_codewords(data: PackedByteArray, version: int) -> PackedByteArray:
	var info: Dictionary = VERSION_TABLE[version]
	var capacity := int(info["data"])

	var bits := _BitWriter.new()
	bits.write(MODE_BYTE, 4)
	bits.write(data.size(), 8)
	for b in data:
		bits.write(b, 8)
	bits.write(0, mini(4, capacity * 8 - bits.length()))
	bits.pad_to_byte()

	var payload := bits.to_bytes()
	var pad_index := 0
	while payload.size() < capacity:
		payload.append(PAD_BYTES[pad_index % 2])
		pad_index += 1

	# Split into blocks, compute ECC per block, then interleave both halves.
	var data_blocks: Array[PackedByteArray] = []
	var ecc_blocks: Array[PackedByteArray] = []
	var offset := 0
	var ecc_len := int(info["ecc"])
	for group in info["blocks"]:
		for _i in int(group[0]):
			var block := payload.slice(offset, offset + int(group[1]))
			offset += int(group[1])
			data_blocks.append(block)
			ecc_blocks.append(_reed_solomon(block, ecc_len))

	var out := PackedByteArray()
	out.append_array(_interleave(data_blocks))
	out.append_array(_interleave(ecc_blocks))
	return out


static func _interleave(blocks: Array[PackedByteArray]) -> PackedByteArray:
	var longest := 0
	for block in blocks:
		longest = maxi(longest, block.size())
	var out := PackedByteArray()
	for i in longest:
		for block in blocks:
			if i < block.size():
				out.append(block[i])
	return out


# --- GF(256) arithmetic ------------------------------------------------------


static func _init_tables() -> void:
	if not _exp_table.is_empty():
		return
	_exp_table.resize(512)
	_log_table.resize(256)
	var x := 1
	for i in 255:
		_exp_table[i] = x
		_log_table[x] = i
		x <<= 1
		if x & 0x100:
			x ^= 0x11D  # QR primitive polynomial
	for i in range(255, 512):
		_exp_table[i] = _exp_table[i - 255]


## Expoente de alfa de um elemento do corpo, para comparar polinômios com as
## tabelas publicadas da norma.
static func alpha_exponent(value: int) -> int:
	_init_tables()
	return -1 if value == 0 else _log_table[value]


static func _mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	return _exp_table[_log_table[a] + _log_table[b]]


## Produto de (x - α^i) para i em 0..degree-1, com o **coeficiente líder
## primeiro** — `poly[0]` é o termo de maior grau e vale sempre 1.
##
## A ordem não é detalhe de estilo: `_reed_solomon` faz divisão sintética e
## depende de `poly[0] == 1` para zerar cada passo. Montar o polinômio na ordem
## inversa produz um ECC completamente errado, e nada no QR resultante denuncia
## isso — padrões, formato, máscara e dados continuam perfeitos, e só um
## decodificador de verdade rejeita o código.
static func _generator_poly(degree: int) -> PackedInt32Array:
	var poly := PackedInt32Array([1])
	for i in degree:
		var next := PackedInt32Array()
		next.resize(poly.size() + 1)
		next.fill(0)
		for j in poly.size():
			next[j] ^= poly[j]
			next[j + 1] ^= _mul(poly[j], _exp_table[i])
		poly = next
	return poly


static func _reed_solomon(data: PackedByteArray, ecc_len: int) -> PackedByteArray:
	_init_tables()
	var gen := _generator_poly(ecc_len)
	var work := PackedInt32Array()
	work.resize(data.size() + ecc_len)
	work.fill(0)
	for i in data.size():
		work[i] = data[i]
	for i in data.size():
		var coefficient := work[i]
		if coefficient == 0:
			continue
		for j in gen.size():
			work[i + j] ^= _mul(gen[j], coefficient)
	var out := PackedByteArray()
	for i in ecc_len:
		out.append(work[data.size() + i])
	return out


# --- matrix construction -----------------------------------------------------


static func _put(grid: PackedByteArray, size: int, row: int, col: int, value: int) -> void:
	grid[row * size + col] = value


static func _at(grid: PackedByteArray, size: int, row: int, col: int) -> int:
	return grid[row * size + col]


static func _set_function(
	modules: PackedByteArray, reserved: PackedByteArray, size: int, row: int, col: int, dark: int
) -> void:
	if row < 0 or row >= size or col < 0 or col >= size:
		return
	_put(modules, size, row, col, dark)
	_put(reserved, size, row, col, 1)


static func _draw_function_patterns(
	modules: PackedByteArray, reserved: PackedByteArray, size: int, version: int
) -> void:
	for i in size:
		# Timing patterns.
		_set_function(modules, reserved, size, 6, i, 1 if i % 2 == 0 else 0)
		_set_function(modules, reserved, size, i, 6, 1 if i % 2 == 0 else 0)

	for origin in [Vector2i(0, 0), Vector2i(0, size - 7), Vector2i(size - 7, 0)]:
		_draw_finder(modules, reserved, size, origin.x, origin.y)

	var centres: Array = VERSION_TABLE[version]["align"]
	for row: int in centres:
		for col: int in centres:
			var on_finder: bool = (row == 6 and col == 6) or (row == 6 and col == size - 7) or (row == size - 7 and col == 6)
			if not on_finder:
				_draw_alignment(modules, reserved, size, row, col)

	# Reserve the format information strips. Index 6 is skipped: those two
	# modules belong to the timing patterns, already drawn above.
	for i in 9:
		if i == 6:
			continue
		_set_function(modules, reserved, size, 8, i, 0)
		_set_function(modules, reserved, size, i, 8, 0)
	for i in 8:
		_set_function(modules, reserved, size, 8, size - 1 - i, 0)
		_set_function(modules, reserved, size, size - 1 - i, 8, 0)
	# The always-dark module.
	_set_function(modules, reserved, size, size - 8, 8, 1)

	if version >= 7:
		_draw_version_bits(modules, reserved, size, version)


static func _draw_finder(
	modules: PackedByteArray, reserved: PackedByteArray, size: int, top: int, left: int
) -> void:
	# 8x8 including the separator, clipped at the board edges.
	for dr in range(-1, 8):
		for dc in range(-1, 8):
			var ring := maxi(absi(dr - 3), absi(dc - 3))
			var dark := 1 if (ring != 2 and ring <= 3) else 0
			_set_function(modules, reserved, size, top + dr, left + dc, dark)


static func _draw_alignment(
	modules: PackedByteArray, reserved: PackedByteArray, size: int, row: int, col: int
) -> void:
	for dr in range(-2, 3):
		for dc in range(-2, 3):
			var ring := maxi(absi(dr), absi(dc))
			_set_function(modules, reserved, size, row + dr, col + dc, 1 if ring != 1 else 0)


static func _draw_version_bits(
	modules: PackedByteArray, reserved: PackedByteArray, size: int, version: int
) -> void:
	var remainder := version
	for _i in 12:
		remainder = (remainder << 1) ^ ((remainder >> 11) * 0x1F25)
	var bits := (version << 12) | remainder
	for i in 18:
		var bit := (bits >> i) & 1
		var far := size - 11 + i % 3
		var near := i / 3
		_set_function(modules, reserved, size, near, far, bit)
		_set_function(modules, reserved, size, far, near, bit)


static func _draw_format_bits(modules: PackedByteArray, size: int, mask: int) -> void:
	var value := (ECC_LEVEL_BITS << 3) | mask
	var remainder := value
	for _i in 10:
		remainder = (remainder << 1) ^ ((remainder >> 9) * 0x537)
	var bits := ((value << 10) | remainder) ^ 0x5412

	for i in 6:
		_put(modules, size, i, 8, (bits >> i) & 1)
	_put(modules, size, 7, 8, (bits >> 6) & 1)
	_put(modules, size, 8, 8, (bits >> 7) & 1)
	_put(modules, size, 8, 7, (bits >> 8) & 1)
	for i in range(9, 15):
		_put(modules, size, 8, 14 - i, (bits >> i) & 1)

	for i in 8:
		_put(modules, size, 8, size - 1 - i, (bits >> i) & 1)
	for i in range(8, 15):
		_put(modules, size, size - 15 + i, 8, (bits >> i) & 1)


## Zig-zag placement: two columns at a time, right to left, skipping the
## vertical timing column.
static func _draw_codewords(
	modules: PackedByteArray, reserved: PackedByteArray, size: int, codewords: PackedByteArray, version: int
) -> void:
	var total_bits := codewords.size() * 8 + int(REMAINDER_BITS[version])
	var bit_index := 0
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var col := right - j
				var upward := ((right + 1) & 2) == 0
				var row := (size - 1 - vert) if upward else vert
				if _at(reserved, size, row, col) == 1 or bit_index >= total_bits:
					continue
				var dark := 0
				if bit_index < codewords.size() * 8:
					dark = (codewords[bit_index >> 3] >> (7 - (bit_index & 7))) & 1
				_put(modules, size, row, col, dark)
				bit_index += 1
		right -= 2


static func _apply_mask(modules: PackedByteArray, reserved: PackedByteArray, size: int, mask: int) -> void:
	for row in size:
		for col in size:
			if _at(reserved, size, row, col) == 1:
				continue
			if _mask_bit(mask, row, col):
				_put(modules, size, row, col, 1 - _at(modules, size, row, col))


static func _mask_bit(mask: int, row: int, col: int) -> bool:
	match mask:
		0:
			return (row + col) % 2 == 0
		1:
			return row % 2 == 0
		2:
			return col % 3 == 0
		3:
			return (row + col) % 3 == 0
		4:
			return (row / 2 + col / 3) % 2 == 0
		5:
			return (row * col) % 2 + (row * col) % 3 == 0
		6:
			return ((row * col) % 2 + (row * col) % 3) % 2 == 0
		_:
			return ((row + col) % 2 + (row * col) % 3) % 2 == 0


# --- mask scoring ------------------------------------------------------------


static func _penalty(modules: PackedByteArray, size: int) -> int:
	var score := 0
	score += _penalty_runs(modules, size)
	score += _penalty_blocks(modules, size)
	score += _penalty_finder_like(modules, size)
	score += _penalty_balance(modules, size)
	return score


static func _penalty_runs(modules: PackedByteArray, size: int) -> int:
	var score := 0
	for line in 2:
		for i in size:
			var run := 1
			var previous := -1
			for j in size:
				var value := _at(modules, size, i, j) if line == 0 else _at(modules, size, j, i)
				if value == previous:
					run += 1
					if run == 5:
						score += 3
					elif run > 5:
						score += 1
				else:
					previous = value
					run = 1
	return score


static func _penalty_blocks(modules: PackedByteArray, size: int) -> int:
	var score := 0
	for row in size - 1:
		for col in size - 1:
			var value := _at(modules, size, row, col)
			var uniform := (
				value == _at(modules, size, row, col + 1)
				and value == _at(modules, size, row + 1, col)
				and value == _at(modules, size, row + 1, col + 1)
			)
			if uniform:
				score += 3
	return score


static func _penalty_finder_like(modules: PackedByteArray, size: int) -> int:
	const PATTERN := [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0]
	var score := 0
	for line in 2:
		for i in size:
			for j in range(size - PATTERN.size() + 1):
				var forward := true
				var backward := true
				for k in PATTERN.size():
					var value := _at(modules, size, i, j + k) if line == 0 else _at(modules, size, j + k, i)
					if value != PATTERN[k]:
						forward = false
					if value != PATTERN[PATTERN.size() - 1 - k]:
						backward = false
				if forward:
					score += 40
				if backward:
					score += 40
	return score


static func _penalty_balance(modules: PackedByteArray, size: int) -> int:
	var dark := 0
	for value in modules:
		dark += value
	var percent := dark * 100 / (size * size)
	return absi(percent - 50) / 5 * 10


class _BitWriter:
	extends RefCounted

	var _bits: PackedByteArray = PackedByteArray()

	func write(value: int, count: int) -> void:
		for i in range(count - 1, -1, -1):
			_bits.append((value >> i) & 1)

	func length() -> int:
		return _bits.size()

	func pad_to_byte() -> void:
		while _bits.size() % 8 != 0:
			_bits.append(0)

	func to_bytes() -> PackedByteArray:
		var out := PackedByteArray()
		for i in range(0, _bits.size(), 8):
			var byte := 0
			for j in 8:
				byte = (byte << 1) | _bits[i + j]
			out.append(byte)
		return out
