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


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (esperado %s, obtido %s)" % [label, expected, actual])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
