class_name Cosmetics
extends RefCounted

## O catálogo visual da loja: o que cada item é e como se desenha.
##
## O preço não mora aqui. Ele é do servidor (coleção `shop_items`, editada no
## painel admin e lida por `Account.fetch_prices`), e item sem preço lá não
## aparece à venda. O visual
## de um jogador (`look`) é um dicionário `{encaixe: id}`, o mesmo que a conta
## guarda e que viaja aos outros aparelhos no aperto de mão (`Net.look_of`).

const BALL := "ball"
const BOARD := "board"
const FINISH := "finish"
const PIECES := "pieces"
const CUE := "cue"
## O perfil: a moldura da foto (`Coaster`), a capa do perfil (`ProfileCover`), um
## título abaixo do nome e a cor do nome (`ProfileStyle`).
const FRAME := "frame"
const BANNER := "banner"
const TITLE := "title"
const NAME_COLOR := "name_color"
## O taco de sempre desenrolado, só para a amostra da loja.
const DEFAULT_CUE := "res://assets/pool/cues/cue_default.png"
## A textura da bola padrão (o mármore que a cor do assento pinta), para a amostra.
const MARBLE := "res://assets/bowling/ball_ball_marble.png"

const ITEMS := {
	"ball_galaxy": {"slot": BALL, "name": "Galáxia", "art": "res://assets/bowling/skins/ball_galaxy.png"},
	"ball_flames": {"slot": BALL, "name": "Chamas", "art": "res://assets/bowling/skins/ball_flames.png"},
	"ball_ocean": {"slot": BALL, "name": "Oceano", "art": "res://assets/bowling/skins/ball_ocean.png"},
	"ball_melon": {"slot": BALL, "name": "Melancia", "art": "res://assets/bowling/skins/ball_melon.png"},
	"ball_wood": {"slot": BALL, "name": "Madeira", "art": "res://assets/bowling/skins/ball_wood.png"},
	"ball_checker": {"slot": BALL, "name": "Xadrez", "art": "res://assets/bowling/skins/ball_checker.png"},
	# As especiais (`art/bowling/build_special_balls.py`): o material também muda.
	# `metallic` e `roughness` como no `StandardMaterial3D`; `glow` acende a própria
	# textura (o escuro quase não brilha); `alpha` é vidro.
	"ball_chrome": {
		"slot": BALL, "name": "Cromada", "art": "res://assets/bowling/skins/ball_chrome.png",
		"metallic": 0.55, "roughness": 0.08,
	},
	"ball_neon": {"slot": BALL, "name": "Neon", "art": "res://assets/bowling/skins/ball_neon.png", "glow": 2.2},
	"ball_crystal": {
		"slot": BALL, "name": "Cristal", "art": "res://assets/bowling/skins/ball_crystal.png",
		"alpha": 0.5, "roughness": 0.02,
	},
	"ball_lava": {"slot": BALL, "name": "Lava", "art": "res://assets/bowling/skins/ball_lava.png", "glow": 1.6},
	"ball_pioneer": {
		"slot": BALL, "name": "Pioneira", "art": "res://assets/bowling/skins/ball_pioneer.png", "glow": 1.3, "testers": true,
	},
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
	# Acabamentos das peças do xadrez e das damas (`PieceRenderer`): o desenho de
	# sempre com outras tintas. Por lado (`white`, `black`), `body` é o corpo,
	# numa cor ou num degradê (lista de cores, de cima para baixo), e `line` o
	# contorno e os detalhes.
	# Molduras da foto: `style` é o desenho em `Coaster._draw_frame`.
	"frame_gold": {"slot": FRAME, "name": "Ouro", "style": "gold"},
	"frame_silver": {"slot": FRAME, "name": "Prata", "style": "silver"},
	"frame_neon": {"slot": FRAME, "name": "Neon", "style": "neon"},
	"frame_flames": {"slot": FRAME, "name": "Chamas", "style": "flames"},
	"frame_laurel": {"slot": FRAME, "name": "Louros", "style": "laurel"},
	"frame_rainbow": {"slot": FRAME, "name": "Arco-íris", "style": "rainbow"},
	# Os de testador (`testers`): o agradecimento a quem testou o app desde o
	# começo, mandados num kit de presente pelo admin. Não se compram nem saem por
	# missão, e a loja só os mostra a quem já tem.
	"frame_pioneer": {"slot": FRAME, "name": "Pioneiro", "style": "pioneer", "testers": true},
	# Capas do perfil: um degradê de cima para baixo (`colors`) e um desenho por
	# cima (`pattern`), em `ProfileCover.paint`.
	"banner_sunset": {"slot": BANNER, "name": "Pôr do sol", "colors": [Color("ff9a5a"), Color("ff5f8f"), Color("6b3fa0")], "pattern": "sun"},
	"banner_night": {"slot": BANNER, "name": "Noite estrelada", "colors": [Color("0b1030"), Color("2a2266")], "pattern": "stars"},
	"banner_felt": {"slot": BANNER, "name": "Feltro", "colors": [Color("1f7a4f"), Color("125236")], "pattern": "felt"},
	"banner_checker": {"slot": BANNER, "name": "Tabuleiro", "colors": [Color("3b3478"), Color("272250")], "pattern": "checker"},
	"banner_waves": {"slot": BANNER, "name": "Ondas", "colors": [Color("2f9bd6"), Color("124a7a")], "pattern": "waves"},
	"banner_aurora": {"slot": BANNER, "name": "Aurora", "colors": [Color("0a1d33"), Color("120f38")], "pattern": "aurora"},
	"banner_pioneer": {
		"slot": BANNER, "name": "Céu dos Pioneiros", "colors": [Color("070a1f"), Color("1b1046"), Color("2a0d3b")],
		"pattern": "pioneer", "testers": true,
	},
	# Títulos: o nome é o texto que aparece. Nunca texto livre.
	"title_pool": {"slot": TITLE, "name": "Rei da Sinuca"},
	"title_chess": {"slot": TITLE, "name": "Mestre do Xadrez"},
	"title_strike": {"slot": TITLE, "name": "Strike!"},
	"title_board": {"slot": TITLE, "name": "Rainha do Tabuleiro"},
	"title_uno": {"slot": TITLE, "name": "Mão de Uno"},
	"title_boteco": {"slot": TITLE, "name": "Lenda do Boteco"},
	"title_lucky": {"slot": TITLE, "name": "Sortudo"},
	"title_unbeaten": {"slot": TITLE, "name": "Imbatível"},
	# Exclusivos: não se compram, saem por missão (`pocketbase/pb_migrations/1764100000_missoes.js`).
	"title_veteran": {"slot": TITLE, "name": "Veterano"},
	"title_champion": {"slot": TITLE, "name": "Campeão"},
	"title_explorer": {"slot": TITLE, "name": "Explorador"},
	# `shine` passa um brilho dourado pelas letras (`ProfileStyle.dress_title`).
	"title_pioneer": {"slot": TITLE, "name": "Testador Fundador", "shine": true, "testers": true},
	# Cores do nome; `rainbow` pinta cada letra de uma cor.
	"name_gold": {"slot": NAME_COLOR, "name": "Ouro", "color": Color("ffd25a")},
	"name_ruby": {"slot": NAME_COLOR, "name": "Rubi", "color": Color("ff5a7a")},
	"name_emerald": {"slot": NAME_COLOR, "name": "Esmeralda", "color": Color("3ee08f")},
	"name_neon": {"slot": NAME_COLOR, "name": "Neon", "color": Color("39e6ff")},
	"name_rainbow": {"slot": NAME_COLOR, "name": "Arco-íris", "rainbow": true},
	# `pioneer`: menta, violeta e ouro correndo pelas letras (`ui/pioneer_text.gdshader`).
	"name_pioneer": {"slot": NAME_COLOR, "name": "Pioneiro", "pioneer": true, "testers": true},
	# Tacos da sinuca (`tools/build_cue_skins.gd`, desenhados por `ui/cue_skin.gdshader`).
	# `glow` é o quanto a cor brilha sozinha.
	"cue_ebony": {"slot": CUE, "name": "Ébano e marfim", "art": "res://assets/pool/cues/cue_ebony.png"},
	"cue_carbon": {"slot": CUE, "name": "Carbono", "art": "res://assets/pool/cues/cue_carbon.png"},
	"cue_flames": {"slot": CUE, "name": "Chamas", "art": "res://assets/pool/cues/cue_flames.png"},
	"cue_neon": {"slot": CUE, "name": "Neon", "art": "res://assets/pool/cues/cue_neon.png", "glow": 1.6},
	"cue_gold": {"slot": CUE, "name": "Ouro", "art": "res://assets/pool/cues/cue_gold.png"},
	"cue_pioneer": {"slot": CUE, "name": "Pioneiro", "art": "res://assets/pool/cues/cue_pioneer.png", "testers": true},
	# Conjuntos de peças do xadrez (`tools/build_piece_sets.gd`): o mesmo nome de
	# arquivo das peças de sempre, noutra pasta. As damas não mudam de formato.
	"pieces_staunton": {"slot": PIECES, "name": "Clássico", "dir": "res://assets/pieces/sets/staunton"},
	"pieces_minimal": {"slot": PIECES, "name": "Minimalista", "dir": "res://assets/pieces/sets/minimal"},
	"pieces_medieval": {"slot": PIECES, "name": "Medieval", "dir": "res://assets/pieces/sets/medieval"},
	"finish_wood": {
		"slot": FINISH, "name": "Madeira",
		"white": {"body": ["#f5dcae", "#e3c28c", "#f2d6a2", "#d9b47a", "#efd09a", "#e0bd84"], "line": "#5a3a1e"},
		"black": {"body": ["#7a4a2a", "#5e3519", "#82512f", "#55301a", "#744526", "#5c3419"], "line": "#f0d3a2"},
	},
	"finish_marble": {
		"slot": FINISH, "name": "Mármore",
		"white": {"body": ["#ffffff", "#ebe7df", "#fbfaf6", "#d9d4ca", "#f4f1ea"], "line": "#57534d"},
		"black": {"body": ["#3a4140", "#1f2423", "#465050", "#191d1c", "#333a39"], "line": "#d5dbd8"},
	},
	"finish_metal": {
		"slot": FINISH, "name": "Ouro e prata",
		"white": {"body": ["#ffffff", "#c3cad3", "#eef2f6", "#9ea8b4", "#e6ebf0"], "line": "#3e4652"},
		"black": {"body": ["#ffe89a", "#c8952a", "#fbe7a4", "#9c6c14", "#e9c25a"], "line": "#3d2604"},
	},
	"finish_neon": {
		"slot": FINISH, "name": "Neon",
		"white": {"body": "#e9fdff", "line": "#00c8ff"},
		"black": {"body": "#1b0f35", "line": "#ff4fd8"},
	},
	# O dos testadores: brancas de pérola mentolada com traço de ouro velho,
	# pretas de céu índigo e violeta com traço dourado.
	"finish_pioneer": {
		"slot": FINISH, "name": "Pioneiro", "testers": true,
		"white": {"body": ["#f2fffb", "#bdf3e4", "#e6fff8", "#a3e6d5", "#d8faf0"], "line": "#6b4c0e"},
		"black": {"body": ["#4a3699", "#1b1046", "#5a43b0", "#140c38", "#33266e"], "line": "#ffd25a"},
	},
	"finish_gems": {
		"slot": FINISH, "name": "Rubi e safira",
		"white": {"body": ["#ff9db0", "#e2324f", "#ffc2cd", "#c21a38", "#ff7a92"], "line": "#4d0613"},
		"black": {"body": ["#5f82ff", "#1d36a8", "#8aa4ff", "#14237a", "#4466e6"], "line": "#e3e9ff"},
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


## O acabamento de peças de um visual, ou vazio para o desenho de sempre.
static func finish_of(look: Dictionary) -> String:
	var id := str(look.get(FINISH, ""))
	return id if ITEMS.has(id) and ITEMS[id]["slot"] == FINISH else ""


## O taco de um visual: `{"art": textura, "glow": brilho}`, ou vazio para o de
## sempre (item que este app não conhece também).
static func cue_skin(look: Dictionary) -> Dictionary:
	var id := str(look.get(CUE, ""))
	if not ITEMS.has(id) or ITEMS[id]["slot"] != CUE:
		return {}
	return {"art": load(ITEMS[id]["art"]), "glow": float(ITEMS[id].get("glow", 0.0))}


## O item de um encaixe do visual, se este app o conhece; vazio senão.
static func item_of(look: Dictionary, slot: String) -> Dictionary:
	var id := str(look.get(slot, ""))
	return ITEMS[id] if ITEMS.has(id) and ITEMS[id]["slot"] == slot else {}


## O estilo da moldura da foto (`Coaster.frame`), ou vazio.
static func frame_of(look: Dictionary) -> String:
	return str(item_of(look, FRAME).get("style", ""))


## O texto do título, ou vazio.
static func title_of(look: Dictionary) -> String:
	return str(item_of(look, TITLE).get("name", ""))


## A pasta do conjunto de peças de um visual, ou vazio para as de sempre.
static func pieces_dir(look: Dictionary) -> String:
	var id := str(look.get(PIECES, ""))
	return str(ITEMS[id]["dir"]) if ITEMS.has(id) and ITEMS[id]["slot"] == PIECES else ""


## As tintas de um acabamento para um lado (`Board.Side`): `{"body", "line"}`,
## ou vazio quando o acabamento não existe.
static func finish_paint(finish: String, side: int) -> Dictionary:
	if not ITEMS.has(finish) or ITEMS[finish]["slot"] != FINISH:
		return {}
	return ITEMS[finish]["white" if side == Board.Side.WHITE else "black"]


## O material especial da bola de uma textura da loja (`metallic`, `roughness`,
## `glow`, `alpha`), ou vazio. Pela textura porque é ela que a pista e a mira já
## recebem (`BowlingLane.tint_ball`).
static func ball_params(skin: Texture2D) -> Dictionary:
	if skin == null:
		return {}
	for id: String in ITEMS:
		var item: Dictionary = ITEMS[id]
		if item["slot"] == BALL and item["art"] == skin.resource_path:
			var params := {}
			for key in ["metallic", "roughness", "glow", "alpha"]:
				if item.has(key):
					params[key] = item[key]
			return params
	return {}


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
