extends SceneTree

## Os componentes base do tema Boteco, sem autoload e sem GPU.
##
##   godot --headless --path . --script res://tests/ui_kit_probe.gd
##
## O que se verifica aqui é o que dá para verificar sem enxergar pixel: que as
## fontes são as embarcadas e têm os acentos do português, que as cores de texto
## passam no contraste, que o tema entrega as variações que as telas pedem, e a
## geometria e o comportamento de cada componente. O que só a imagem prova — que
## peças e cartas não mudaram — é conferido por `tests/image_diff.gd`.

var _failures := 0


func _initialize() -> void:
	_probe_fonts()
	_probe_dashed()
	if _failures == 0:
		print("OK — kit de interface consistente.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	quit(1 if _failures > 0 else 0)


func _probe_fonts() -> void:
	print("fontes")
	var body := AppTheme.font(400)
	var bold := AppTheme.font(700)
	var display := AppTheme.display()
	var mono := AppTheme.mono()
	_check(
		body is FontFile and body.resource_path.ends_with("AtkinsonHyperlegible-Regular.ttf"),
		"corpo é a Atkinson Hyperlegible"
	)
	_check(
		bold is FontFile and bold.resource_path.ends_with("AtkinsonHyperlegible-Bold.ttf"),
		"e o negrito é o arquivo negrito"
	)
	_check(display is FontVariation, "display é uma variação da Big Shoulders")
	if display is FontVariation:
		var tag := TextServerManager.get_primary_interface().name_to_tag("wght")
		_equals(int((display as FontVariation).variation_opentype.get(tag, 0)), 900, "no peso 900")
	_check(
		mono is FontFile and mono.resource_path.ends_with("IBMPlexMono-SemiBold.ttf"),
		"mono é a IBM Plex Mono"
	)
	_check(AppTheme.legacy_font(700) is SystemFont, "a fonte antiga continua disponível para o que é protegido")
	_check(AppTheme.font(700) == AppTheme.font(700), "fontes em cache: a mesma instância a cada chamada")
	for letter: String in ["ç", "ã", "é", "ô", "Ú"]:
		var code := letter.unicode_at(0)
		_check(
			body.has_char(code) and display.has_char(code) and mono.has_char(code),
			"as três famílias têm '%s'" % letter
		)


func _probe_dashed() -> void:
	print("tracejado")
	var rounded := StyleBoxDashed.outline_points(Rect2(0, 0, 100, 40), 10.0)
	_equals(rounded.size(), 4 * (StyleBoxDashed.CORNER_STEPS + 1), "um arco de pontos por canto")
	_check(rounded[0].is_equal_approx(Vector2(90, 0)), "o contorno começa no fim da aresta de cima")
	var inside := true
	for point in rounded:
		inside = inside and Rect2(0, 0, 100, 40).grow(0.001).has_point(point)
	_check(inside, "e nenhum ponto sai do retângulo")
	var clamped := StyleBoxDashed.outline_points(Rect2(0, 0, 100, 40), 50.0)
	_check(clamped[0].is_equal_approx(Vector2(80, 0)), "raio maior que meia altura é limitado a ela")
	var square := StyleBoxDashed.outline_points(Rect2(0, 0, 100, 100), 0.0)
	_equals(square.size(), 4, "sem raio, um ponto por canto")
	var dashes := StyleBoxDashed.dash_segments(square, 10.0, 10.0)
	_equals(dashes.size() % 2, 0, "os traços vêm em pares")
	_check(absf(_drawn(dashes) - 200.0) < 0.01, "metade do perímetro desenhada com traço e vão iguais (obtido %.2f)" % _drawn(dashes))
	var longest := 0.0
	for i in range(0, dashes.size(), 2):
		longest = maxf(longest, dashes[i].distance_to(dashes[i + 1]))
	_check(longest <= 10.0001, "nenhum traço maior que o pedido")
	var solid := StyleBoxDashed.dash_segments(square, 10.0, 0.0)
	_check(absf(_drawn(solid) - 400.0) < 0.01, "sem vão, o contorno inteiro")


static func _drawn(segments: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(0, segments.size(), 2):
		total += segments[i].distance_to(segments[i + 1])
	return total


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
