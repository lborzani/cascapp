class_name GameRulesFormat
extends Resource

## Um formato de um jogo que tem mais de um jeito de jogar — a sinuca tem dois, e
## eles discordam até no que é a bola que taca.
##
## Mesmos campos da página inteira, porque cada formato **é** uma página inteira:
## objetivo, passos e avisos próprios. O que o jogo tem em comum fica no
## [GameRulesDoc] que carrega os formatos.

@export var title := ""
@export_multiline var objective := ""
@export var steps := PackedStringArray()
@export var notes := PackedStringArray()
