class_name Cosmetics
extends RefCounted

## O catálogo visual da loja: o que cada item é e como se desenha.
##
## O preço não mora aqui. Ele é do servidor (`pocketbase/pb_hooks/loja.js`, lido
## por `Account.fetch_prices`), e item sem preço lá não aparece à venda. O visual
## de um jogador (`look`) é um dicionário `{encaixe: id}`, o mesmo que a conta
## guarda e que viaja aos outros aparelhos no aperto de mão (`Net.look_of`).

const BALL := "ball"
## A textura da bola padrão (o mármore que a cor do assento pinta), para a amostra.
const MARBLE := "res://assets/bowling/ball_ball_marble.png"

const ITEMS := {
	"ball_galaxy": {"slot": BALL, "name": "Galáxia", "art": "res://assets/bowling/skins/ball_galaxy.png"},
	"ball_flames": {"slot": BALL, "name": "Chamas", "art": "res://assets/bowling/skins/ball_flames.png"},
	"ball_ocean": {"slot": BALL, "name": "Oceano", "art": "res://assets/bowling/skins/ball_ocean.png"},
	"ball_melon": {"slot": BALL, "name": "Melancia", "art": "res://assets/bowling/skins/ball_melon.png"},
	"ball_wood": {"slot": BALL, "name": "Madeira", "art": "res://assets/bowling/skins/ball_wood.png"},
	"ball_checker": {"slot": BALL, "name": "Xadrez", "art": "res://assets/bowling/skins/ball_checker.png"},
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
