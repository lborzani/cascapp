class_name Avatar
extends RefCounted

## A foto do jogador, pronta para subir para a conta.
##
## Uma foto de celular tem 3 a 8 MB; o avatar aparece numa bolacha de 40 a 96
## px. Por isso a foto é recortada no quadrado do centro, reduzida a `SIZE` e
## comprimida em WebP **no aparelho**, antes de qualquer envio: o servidor de
## casa guarda e serve arquivos de dezenas de KB, e o 4G de quem joga agradece.
## O teto do servidor (`pocketbase/pb_migrations/1760650000_perfil.js`) é
## `MAX_BYTES`, e quem pular o app bate nele.

const SIZE := 256
const MAX_BYTES := 100 * 1024
## Da melhor para a pior. Uma foto comum fica na primeira; ruído (grama,
## cascalho) precisa descer, e a última garante caber.
const QUALITIES: Array[float] = [0.8, 0.6, 0.4, 0.2]


## Os bytes de uma imagem qualquer (PNG, JPEG, WebP) viram o WebP do avatar.
## Vazio quando os bytes não são imagem que o Godot leia.
static func compress(bytes: PackedByteArray) -> PackedByteArray:
	var image := decode(bytes)
	if image == null:
		return PackedByteArray()
	_upright(image, jpeg_orientation(bytes))
	var side := mini(image.get_width(), image.get_height())
	image = image.get_region(Rect2i(
		(image.get_width() - side) / 2, (image.get_height() - side) / 2, side, side
	))
	image.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	var out := PackedByteArray()
	for quality in QUALITIES:
		out = image.save_webp_to_buffer(true, quality)
		if out.size() <= MAX_BYTES:
			break
	return out


## Pela assinatura dos bytes, e não pela extensão: no Android o seletor devolve
## um `content://` sem extensão nenhuma.
static func decode(bytes: PackedByteArray) -> Image:
	if bytes.size() < 12:
		return null
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		error = image.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		error = image.load_jpg_from_buffer(bytes)
	elif bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		error = image.load_webp_from_buffer(bytes)
	if error != OK or image.is_empty():
		return null
	image.convert(Image.FORMAT_RGB8)
	return image


static func texture(bytes: PackedByteArray) -> Texture2D:
	var image := decode(bytes)
	return ImageTexture.create_from_image(image) if image != null else null


## A orientação EXIF de um JPEG (1 a 8), ou 1 sem ela.
##
## A câmera grava a foto deitada e anota no EXIF quanto girar para exibir. O
## Godot não lê essa anotação, e sem isto metade das fotos tiradas em pé virava
## avatar deitado.
static func jpeg_orientation(bytes: PackedByteArray) -> int:
	if bytes.size() < 4 or bytes[0] != 0xFF or bytes[1] != 0xD8:
		return 1
	var at := 2
	while at + 4 <= bytes.size() and bytes[at] == 0xFF:
		var marker := bytes[at + 1]
		var length := (bytes[at + 2] << 8) | bytes[at + 3]
		if marker == 0xE1 and bytes.slice(at + 4, at + 10) == PackedByteArray([0x45, 0x78, 0x69, 0x66, 0, 0]):
			return _tiff_orientation(bytes.slice(at + 10, at + 2 + length))
		if marker == 0xDA:
			break
		at += 2 + length
	return 1


static func _tiff_orientation(tiff: PackedByteArray) -> int:
	if tiff.size() < 8:
		return 1
	var little := tiff[0] == 0x49
	var read16 := func(at: int) -> int:
		return (tiff[at] | (tiff[at + 1] << 8)) if little else ((tiff[at] << 8) | tiff[at + 1])
	var ifd: int = (read16.call(4) | (read16.call(6) << 16)) if little else ((read16.call(4) << 16) | read16.call(6))
	if ifd + 2 > tiff.size():
		return 1
	var count: int = read16.call(ifd)
	for entry in count:
		var at := ifd + 2 + entry * 12
		if at + 12 > tiff.size():
			break
		if read16.call(at) == 0x0112:
			return clampi(read16.call(at + 8), 1, 8)
	return 1


## Só os giros. As orientações espelhadas (2, 4, 5, 7) são de câmera frontal
## com espelho ligado, e uma selfie espelhada continua sendo o rosto certo.
static func _upright(image: Image, orientation: int) -> void:
	match orientation:
		3, 4:
			image.rotate_180()
		5, 6:
			image.rotate_90(CLOCKWISE)
		7, 8:
			image.rotate_90(COUNTERCLOCKWISE)
