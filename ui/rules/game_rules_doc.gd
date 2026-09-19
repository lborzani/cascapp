class_name GameRulesDoc
extends Resource

## As regras de um jogo, como o jogador lê em "Como jogar".
##
## Um recurso por jogo em `data/rules/<id>.tres`, editável no inspetor, e nenhum
## texto de regra dentro de cena: a página e a gaveta de regras da mesa leem
## daqui, e mudar uma frase não pede abrir uma tela.
##
## O conteúdo foi escrito a partir do código de regras de cada jogo, e não de
## memória — a página não pode descrever um jogo diferente do que o app joga.
## Quem mudar uma regra em `core/` muda a frase aqui junto.
##
## Mora em `ui/`, e não em `core/`: texto é apresentação, e `core/` não conhece
## quem o mostra.

@export var title := ""
@export_multiline var objective := ""
## Sequência de verdade — o que se faz na ordem em que se faz —, e por isso a
## página numera.
@export var steps := PackedStringArray()
## O que não é passo: faltas, empates, exceções, avisos.
@export var notes := PackedStringArray()
## Um formato por bloco, quando o jogo tem mais de um. Vazio no resto.
@export var formats: Array[GameRulesFormat] = []

const FOLDER := "res://data/rules"


## As regras de um jogo pelo id do catálogo, ou `null` se ele ainda não tem.
static func load_for(id: StringName) -> GameRulesDoc:
	var path := "%s/%s.tres" % [FOLDER, id]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GameRulesDoc
