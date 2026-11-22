class_name Cosmetics
extends RefCounted

## O catálogo visual da loja: o que cada item é e como se desenha.
##
## O preço não mora aqui. Ele é do servidor (`pocketbase/pb_hooks/loja.js`, lido
## por `Account.fetch_prices`), e item sem preço lá não aparece à venda. O visual
## de um jogador (`look`) é um dicionário `{encaixe: id}`, o mesmo que a conta
## guarda e que viaja aos outros aparelhos no aperto de mão (`Net.look_of`).

const BALL := "ball"
const BOARD := "board"
## A textura da bola padrão (o mármore que a cor do assento pinta), para a amostra.
const MARBLE := "res://assets/bowling/ball_ball_marble.png"

const ITEMS := {
	"ball_galaxy": {"slot": BALL, "name": "Galáxia", "art": "res://assets/bowling/skins/ball_galaxy.png"},
	"ball_flames": {"slot": BALL, "name": "Chamas", "art": "res://assets/bowling/skins/ball_flames.png"},
	"ball_ocean": {"slot": BALL, "name": "Oceano", "art": "res://assets/bowling/skins/ball_ocean.png"},
	"ball_melon": {"slot": BALL, "name": "Melancia", "art": "res://assets/bowling/skins/ball_melon.png"},
	"ball_wood": {"slot": BALL, "name": "Madeira", "art": "res://assets/bowling/skins/ball_wood.png"},
	"ball_checker": {"slot": BALL, "name": "Xadrez", "art": "res://assets/bowling/skins/ball_checker.png"},
	# Tabuleiros do xadrez e das damas (`BoardView`). `light`/`dark` são as casas,
	# `last`/`last_dark` o último lance em cada uma, `frame` a moldura. Com
	# `texture`, a casa é a textura (tons de cinza, de `tools/build_board_textures.gd`)
	# multiplicada pela cor; `turn` deita a textura nas casas escuras, para o veio
	# da madeira alternar.
	"board_wood": {
		"slot": BOARD, "name": "Madeira", "light": Color("eccb98"), "dark": Color("a8683a"),
		"frame": Color("4a2c17"), "last": Color("f7e27a"), "last_dark": Color("d9b23f"),
		"texture": "res://assets/boards/wood.png", "turn": true,
	},
	"board_marble": {
		"slot": BOARD, "name": "Mármore", "light": Color("f4f1ea"), "dark": Color("7d8a84"),
		"frame": Color("33393a"), "last": Color("e3f08e"), "last_dark": Color("b4c45a"),
		"texture": "res://assets/boards/marble.png",
	},
	"board_tournament": {
		"slot": BOARD, "name": "Torneio", "light": Color("eeeed2"), "dark": Color("769656"),
		"frame": Color("2c3a24"), "last": Color("f6f68a"), "last_dark": Color("bbcb44"),
	},
	"board_ocean": {
		"slot": BOARD, "name": "Oceano", "light": Color("dcf0f6"), "dark": Color("4f8db3"),
		"frame": Color("143a52"), "last": Color("fff09a"), "last_dark": Color("e2c35a"),
	},
	"board_neon": {
		"slot": BOARD, "name": "Neon", "light": Color("e23ec6"), "dark": Color("3fe6ff"),
		"frame": Color("120b24"), "last": Color("e8ff5a"), "last_dark": Color("e8ff5a"),
		"texture": "res://assets/boards/neon.png",
	},
	"board_candy": {
		"slot": BOARD, "name": "Doces", "light": Color("fff4e6"), "dark": Color("ff86b4"),
		"frame": Color("8a3a5c"), "last": Color("fff08a"), "last_dark": Color("ffc95a"),
		"texture": "res://assets/boards/candy.png",
	},
}

## O tabuleiro sem skin: o violeta do tema.
const DEFAULT_BOARD := {
	"light": AppTheme.BOARD_LIGHT, "dark": AppTheme.BOARD_DARK, "frame": AppTheme.BOARD_FRAME,
	"last": AppTheme.LAST_MOVE, "last_dark": AppTheme.LAST_MOVE_DARK,
}


## Os itens de um encaixe, na ordem do catálogo.
static func of_slot(slot: String) -> Array[String]:
	var found: Array[String] = []
	for id: String in ITEMS:
		if ITEMS[id]["slot"] == slot:
			found.append(id)
	return found


static func name_of(id: String) -> String:
	return str(ITEMS.get(id, {}).get("name", id))


## A textura da bola de um visual, ou `null` para a bola padrão (o mármore na cor
## do assento). Item que este app não conhece (versão mais nova do outro lado)
## também cai no padrão.
static func ball_texture(look: Dictionary) -> Texture2D:
	var id := str(look.get(BALL, ""))
	if not ITEMS.has(id):
		return null
	return load(ITEMS[id]["art"]) as Texture2D


## A skin de tabuleiro de um visual (as chaves de `DEFAULT_BOARD`, mais `texture`
## já carregada e `turn`), ou o padrão. Item desconhecido também cai no padrão.
static func board_skin(look: Dictionary) -> Dictionary:
	var id := str(look.get(BOARD, ""))
	if not ITEMS.has(id) or ITEMS[id]["slot"] != BOARD:
		return DEFAULT_BOARD
	var skin: Dictionary = ITEMS[id].duplicate()
	if skin.has("texture"):
		skin["texture"] = load(skin["texture"])
	return skin


## Um visual vindo da rede, só com encaixes e ids em texto curto. O que não
## passa vira vazio: visual é enfeite, e nunca vale quebrar a partida por ele.
static func clean(raw: Variant) -> Dictionary:
	if not raw is Dictionary or (raw as Dictionary).size() > 12:
		return {}
	var out := {}
	for slot: Variant in raw:
		var item: Variant = raw[slot]
		if slot is String and item is String and (slot as String).length() <= 20 and (item as String).length() <= 40:
			out[slot] = item
	return out
