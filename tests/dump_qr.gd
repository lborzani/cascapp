extends SceneTree

## Salva um PNG do QR de pareamento para conferir a leitura com a câmera de um
## celular de verdade — o único teste que prova que o codificador está certo.
##
##   godot --headless --path . --script res://tests/dump_qr.gd

const PairingLib := preload("res://autoload/pairing.gd")
const MODULE_PX := 12
const QUIET_ZONE := 4
const OUTPUT_PATH := "user://qr_sample.png"


func _initialize() -> void:
	var payload := PairingLib.build_payload(&"chess", "ABC123")
	var code := QrEncoder.encode(payload)
	var size := int(code["size"])
	var modules: PackedByteArray = code["modules"]

	var side := (size + QUIET_ZONE * 2) * MODULE_PX
	var image := Image.create(side, side, false, Image.FORMAT_RGB8)
	image.fill(Color.WHITE)
	for row in size:
		for col in size:
			if modules[row * size + col] == 0:
				continue
			var origin := Vector2i((col + QUIET_ZONE) * MODULE_PX, (row + QUIET_ZONE) * MODULE_PX)
			image.fill_rect(Rect2i(origin, Vector2i(MODULE_PX, MODULE_PX)), Color.BLACK)

	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		printerr("Falha ao salvar o PNG: %d" % error)
		quit(1)
		return
	print("payload: %s" % payload)
	print("versão %d, máscara %d, %dx%d módulos" % [int(code["version"]), int(code["mask"]), size, size])
	print("PNG salvo em %s" % ProjectSettings.globalize_path(OUTPUT_PATH))
	quit(0)
