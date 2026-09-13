extends Node

## Regras do Uno, sem tela.
##
##   godot --headless --path . res://tests/uno_probe.tscn
##
## Três coisas erram em silêncio neste jogo, e são elas que este arquivo persegue:
##
## - **o sorteio**. Se o baralho ou o rembaralho saírem de `randi()` em vez do
##   gerador guardado no estado, os N aparelhos divergem no meio de uma partida
##   longa sem nada falhar. Aqui isso vira uma comparação entre duas partidas com
##   a mesma semente;
## - **a troca de mãos**. Mover um `PackedInt32Array` de uma chave de `meta` para
##   outra deixa as duas chaves compartilhando o mesmo buffer, e o `clone()` do
##   `MatchState` é raso. O sintoma é a variante que o bot explorou vazar para a
##   partida de verdade — nada falha, só a posição fica errada;
## - **a lista de lances vazia**. Um estado sem lance possível trava a vez, e no
##   replay isso não é uma tela parada: é o histórico deixando de ser reproduzível.

const RULES := preload("res://core/uno_rules.gd")

## Fixa: uma partida que passa hoje e falha amanhã por sorte diferente não é um
## teste, é um sorteio.
const SEED := 20260813

var _failures := 0
var _rules: UnoRules = null


func _ready() -> void:
	_rules = _make(4, true)
	_probe_deck()
	_probe_deal()
	_probe_determinism()
	_probe_playable()
	_probe_actions()
	_probe_draw()
	_probe_sevens()
	_probe_clone_isolation()
	_probe_last_card()
	_probe_reshuffle()
	_probe_replay()
	_probe_option()
	_probe_bot()

	if _failures == 0:
		print("OK — regras do Uno consistentes.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _make(seats: int, sevens: bool, match_seed := SEED) -> UnoRules:
	var rules := RULES.new()
	rules.seats = seats
	rules.sevens = sevens
	rules.match_seed = match_seed
	return rules


# --- baralho ------------------------------------------------------------------


## As 108 cartas, e a contagem de cada espécie. Um erro aqui é um baralho que
## joga quase certo: falta um 5 azul e ninguém percebe a partida inteira.
func _probe_deck() -> void:
	print("baralho")
	var deck := UnoRules.full_deck()
	_equals(deck.size(), UnoRules.DECK_SIZE, "o baralho tem 108 cartas")

	var count := {}
	for card in deck:
		count[card] = int(count.get(card, 0)) + 1

	_equals(count[UnoRules.card(UnoRules.CardColor.RED, 0)], 1, "um zero por cor")
	_equals(count[UnoRules.card(UnoRules.CardColor.BLUE, 7)], 2, "dois de cada número de 1 a 9")
	_equals(count[UnoRules.card(UnoRules.CardColor.GREEN, UnoRules.SKIP)], 2, "dois pula por cor")
	_equals(count[UnoRules.card(UnoRules.CardColor.YELLOW, UnoRules.REVERSE)], 2, "dois inverte por cor")
	_equals(count[UnoRules.card(UnoRules.CardColor.RED, UnoRules.DRAW_TWO)], 2, "dois +2 por cor")
	_equals(count[UnoRules.card(UnoRules.CardColor.WILD, UnoRules.WILD)], 4, "quatro curingas")
	_equals(count[UnoRules.card(UnoRules.CardColor.WILD, UnoRules.WILD_FOUR)], 4, "quatro curingas +4")

	# A codificação tem de sobreviver à ida e à volta, senão uma carta jogada num
	# aparelho vira outra no vizinho.
	var wild_four := UnoRules.card(UnoRules.CardColor.WILD, UnoRules.WILD_FOUR)
	_equals(UnoRules.color_of_card(wild_four), UnoRules.CardColor.WILD, "o curinga +4 se diz curinga")
	_equals(UnoRules.value_of_card(wild_four), UnoRules.WILD_FOUR, "e se diz +4")
	_check(UnoRules.is_wild(wild_four), "e é reconhecido como curinga")
	_check(not UnoRules.is_wild(UnoRules.card(UnoRules.CardColor.BLUE, 9)), "um 9 azul não é")


func _probe_deal() -> void:
	print("distribuição")
	var state := _rules.initial_state()
	for seat in 4:
		_equals(UnoRules.hand_size(state, seat), UnoRules.HAND_SIZE, "o assento %d recebe 7" % seat)

	var top := UnoRules.top_card(state)
	_check(not UnoRules.is_wild(top), "a primeira virada não é curinga")
	_equals(
		UnoRules.active_color(state), UnoRules.color_of_card(top),
		"e a cor ativa é a dela"
	)
	_equals(UnoRules.turn_of(state), 0, "o primeiro assento começa")
	_equals(UnoRules.direction_of(state), 1, "e o jogo anda para a frente")
	# 108 = 4 mãos de 7 + a virada + o que sobrou no monte.
	_equals(
		UnoRules.deck_of(state).size(), UnoRules.DECK_SIZE - 4 * UnoRules.HAND_SIZE - 1,
		"e o resto do baralho fica no monte"
	)
	_equals(UnoRules.pile_of(state).size(), 1, "com uma carta no descarte")


## Duas partidas com a mesma semente são o mesmo baralho — e com sementes
## diferentes, não. O segundo lado importa tanto quanto o primeiro: um gerador
## quebrado que devolve sempre o mesmo número passaria no primeiro teste.
func _probe_determinism() -> void:
	print("determinismo do sorteio")
	var first := _make(4, true).initial_state()
	var again := _make(4, true).initial_state()
	var other := _make(4, true, SEED + 1).initial_state()

	for seat in 4:
		_equals(
			UnoRules.hand_of(again, seat), UnoRules.hand_of(first, seat),
			"a mesma semente dá a mesma mão ao assento %d" % seat
		)
	_equals(
		UnoRules.deck_of(again), UnoRules.deck_of(first), "e o mesmo monte"
	)
	_check(
		UnoRules.hand_of(other, 0) != UnoRules.hand_of(first, 0),
		"e uma semente diferente dá outra mão"
	)

	# Semente zero é o ponto fixo do xorshift: sem a defesa, o baralho sai na
	# ordem de fábrica e as quatro mãos ficam sendo cor por cor.
	var zeroed := _make(4, true, 0).initial_state()
	_check(
		UnoRules.deck_of(zeroed) != UnoRules.full_deck().slice(0, UnoRules.deck_of(zeroed).size()),
		"semente zero ainda embaralha"
	)


# --- o que pode ser jogado ----------------------------------------------------


func _probe_playable() -> void:
	print("carta jogável")
	var state := _rig(4, true, [
		[UnoRules.card(UnoRules.CardColor.RED, 3)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))

	_check(
		UnoRules.is_playable(state, UnoRules.card(UnoRules.CardColor.RED, 9)),
		"a cor ativa casa"
	)
	_check(
		UnoRules.is_playable(state, UnoRules.card(UnoRules.CardColor.BLUE, 5)),
		"o mesmo número casa em outra cor"
	)
	_check(
		not UnoRules.is_playable(state, UnoRules.card(UnoRules.CardColor.BLUE, 9)),
		"cor e número diferentes não casam"
	)
	_check(
		UnoRules.is_playable(state, UnoRules.card(UnoRules.CardColor.WILD, UnoRules.WILD)),
		"o curinga casa sempre"
	)

	# Depois de um curinga vale a cor declarada, e "o valor do curinga" não é nada
	# que uma carta comum possa igualar.
	var after_wild := _rig(4, true, [[]], UnoRules.card(UnoRules.CardColor.WILD, UnoRules.WILD))
	after_wild.meta[UnoRules.COLOR] = UnoRules.CardColor.GREEN
	_check(
		UnoRules.is_playable(after_wild, UnoRules.card(UnoRules.CardColor.GREEN, 2)),
		"sobre um curinga vale a cor declarada"
	)
	_check(
		not UnoRules.is_playable(after_wild, UnoRules.card(UnoRules.CardColor.RED, 2)),
		"e não o valor dele"
	)

	# Cartas repetidas na mão dariam lances idênticos, e a tela ofereceria a mesma
	# escolha duas vezes.
	var doubled := _rig(4, true, [
		[UnoRules.card(UnoRules.CardColor.RED, 3), UnoRules.card(UnoRules.CardColor.RED, 3)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	_equals(
		_rules.generate_moves(doubled).size(), 2,
		"duas cartas iguais na mão dão um lance de jogar, mais o de comprar"
	)


func _probe_actions() -> void:
	print("cartas de ação")
	var skip := _rig(4, true, [
		[UnoRules.card(UnoRules.CardColor.RED, UnoRules.SKIP), UnoRules.card(UnoRules.CardColor.BLUE, 1)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	_rules.apply_move(skip, _find(skip, UnoRules.card(UnoRules.CardColor.RED, UnoRules.SKIP)))
	_equals(UnoRules.turn_of(skip), 2, "o pula salta o vizinho")

	var reverse := _rig(4, true, [
		[UnoRules.card(UnoRules.CardColor.RED, UnoRules.REVERSE), UnoRules.card(UnoRules.CardColor.BLUE, 1)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	_rules.apply_move(reverse, _find(reverse, UnoRules.card(UnoRules.CardColor.RED, UnoRules.REVERSE)))
	_equals(UnoRules.direction_of(reverse), -1, "o inverte troca o sentido")
	_equals(UnoRules.turn_of(reverse), 3, "e a vez vai para o outro lado da mesa")

	# Numa mesa de dois, inverter é pular: a vez volta para quem jogou.
	var duel := _make(2, true)
	var heads_up := _rig(2, true, [
		[UnoRules.card(UnoRules.CardColor.RED, UnoRules.REVERSE), UnoRules.card(UnoRules.CardColor.BLUE, 1)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	duel.apply_move(heads_up, _find_with(duel, heads_up, UnoRules.card(UnoRules.CardColor.RED, UnoRules.REVERSE)))
	_equals(UnoRules.turn_of(heads_up), 0, "numa mesa de dois, inverter é pular")

	var two := _rig(4, true, [
		[UnoRules.card(UnoRules.CardColor.RED, UnoRules.DRAW_TWO), UnoRules.card(UnoRules.CardColor.BLUE, 1)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	var before := UnoRules.hand_size(two, 1)
	_rules.apply_move(two, _find(two, UnoRules.card(UnoRules.CardColor.RED, UnoRules.DRAW_TWO)))
	_equals(UnoRules.hand_size(two, 1), before + 2, "o +2 faz o vizinho comprar duas")
	_equals(UnoRules.turn_of(two), 2, "e ele perde a vez")

	var four := _rig(4, true, [
		[UnoRules.card(UnoRules.CardColor.WILD, UnoRules.WILD_FOUR), UnoRules.card(UnoRules.CardColor.BLUE, 1)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	var before_four := UnoRules.hand_size(four, 1)
	var wild_move := _find_colored(four, UnoRules.card(UnoRules.CardColor.WILD, UnoRules.WILD_FOUR), UnoRules.CardColor.GREEN)
	_rules.apply_move(four, wild_move)
	_equals(UnoRules.hand_size(four, 1), before_four + 4, "o +4 faz o vizinho comprar quatro")
	_equals(UnoRules.turn_of(four), 2, "e ele perde a vez")
	_equals(UnoRules.active_color(four), UnoRules.CardColor.GREEN, "a cor declarada passa a valer")
	# O curinga entra no descarte **sem** a cor declarada: pintá-lo faria o
	# rembaralho devolver ao monte um curinga que já não é curinga.
	_check(
		UnoRules.is_wild(UnoRules.top_card(four)),
		"e o curinga continua curinga no descarte"
	)

	_equals(
		_rules.generate_moves(
			_rig(4, true, [[UnoRules.card(UnoRules.CardColor.WILD, UnoRules.WILD)]], UnoRules.card(UnoRules.CardColor.RED, 5))
		).size(),
		UnoRules.COLOR_COUNT + 1,
		"um curinga na mão dá um lance por cor, mais o de comprar"
	)


## Comprar não encerra a vez quando a carta comprada serve — e quando não serve,
## encerra.
func _probe_draw() -> void:
	print("compra")
	var lucky := _rig(4, true, [
		[UnoRules.card(UnoRules.CardColor.BLUE, 9)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	# Monte com uma carta que serve no topo (o topo é o fim do vetor).
	lucky.meta[UnoRules.DECK] = PackedInt32Array([UnoRules.card(UnoRules.CardColor.RED, 2)])
	_rules.apply_move(lucky, _find_kind(lucky, UnoRules.DRAW))
	_equals(UnoRules.turn_of(lucky), 0, "comprar carta que serve não passa a vez")
	_check(UnoRules.drew(lucky), "e o estado marca que já se comprou")

	var moves := _rules.generate_moves(lucky)
	_equals(moves.size(), 2, "e sobram dois lances: jogar a comprada ou passar")
	_equals(
		UnoRules.card_of(moves[0]), UnoRules.card(UnoRules.CardColor.RED, 2),
		"o de jogar é o da carta comprada, não o da mão antiga"
	)
	_equals(UnoRules.kind_of(moves[1]), UnoRules.PASS, "e o outro é passar")

	_rules.apply_move(lucky, moves[1])
	_equals(UnoRules.turn_of(lucky), 1, "passar entrega a vez")
	_check(not UnoRules.drew(lucky), "e limpa a marca da compra")

	var unlucky := _rig(4, true, [
		[UnoRules.card(UnoRules.CardColor.BLUE, 9)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	unlucky.meta[UnoRules.DECK] = PackedInt32Array([UnoRules.card(UnoRules.CardColor.GREEN, 4)])
	_rules.apply_move(unlucky, _find_kind(unlucky, UnoRules.DRAW))
	_equals(UnoRules.turn_of(unlucky), 1, "comprar carta que não serve passa a vez")
	_equals(UnoRules.hand_size(unlucky, 0), 2, "e a carta fica na mão")

	# Monte e descarte esgotados: não há o que comprar, e a vez **precisa** andar.
	var dry := _rig(4, true, [
		[UnoRules.card(UnoRules.CardColor.BLUE, 9)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	dry.meta[UnoRules.DECK] = PackedInt32Array()
	_rules.apply_move(dry, _find_kind(dry, UnoRules.DRAW))
	_equals(UnoRules.turn_of(dry), 1, "sem baralho para comprar, a vez passa mesmo assim")

	# A lista nunca é vazia: sem o lance de comprar, uma mão sem carta jogável
	# travaria a vez para sempre.
	var stuck := _rig(4, true, [
		[UnoRules.card(UnoRules.CardColor.BLUE, 9)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	var only := _rules.generate_moves(stuck)
	_equals(only.size(), 1, "uma mão sem carta jogável tem um lance")
	_equals(UnoRules.kind_of(only[0]), UnoRules.DRAW, "e ele é comprar")


# --- a regra da casa ----------------------------------------------------------


func _probe_sevens() -> void:
	print("regra do 0 e do 7")
	var seven := UnoRules.card(UnoRules.CardColor.RED, 7)

	# Desligada, o 7 é um número comum: um lance só, sem alvo.
	var plain := _make(4, false)
	var off := _rig(4, false, [[seven]], UnoRules.card(UnoRules.CardColor.RED, 5))
	var off_moves := plain.generate_moves(off)
	_equals(off_moves.size(), 2, "desligada, o 7 dá um lance de jogar mais o de comprar")
	_equals(UnoRules.target_of(off_moves[0]), -1, "e sem alvo nenhum")

	# Ligada, um lance por adversário.
	var on := _rig(4, true, [[seven]], UnoRules.card(UnoRules.CardColor.RED, 5))
	var on_moves := _rules.generate_moves(on)
	_equals(on_moves.size(), 4, "ligada, o 7 dá um lance por adversário mais o de comprar")

	# A troca: mão inteira de um pela do outro.
	var swap := _rig(4, true, [
		[seven, UnoRules.card(UnoRules.CardColor.BLUE, 1)],
		[UnoRules.card(UnoRules.CardColor.GREEN, 2)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	_rules.apply_move(swap, _find_target(swap, seven, 1))
	_equals(
		UnoRules.hand_of(swap, 0), PackedInt32Array([UnoRules.card(UnoRules.CardColor.GREEN, 2)]),
		"o 7 entrega a mão do alvo a quem jogou"
	)
	_equals(
		UnoRules.hand_of(swap, 1), PackedInt32Array([UnoRules.card(UnoRules.CardColor.BLUE, 1)]),
		"e a de quem jogou ao alvo, já sem o 7"
	)
	_equals(UnoRules.turn_of(swap), 1, "e a vez segue normalmente")

	# Numa mesa de dois não há com quem escolher trocar.
	var duel := _make(2, true)
	var heads_up := _rig(2, true, [[seven, UnoRules.card(UnoRules.CardColor.BLUE, 1)], []],
		UnoRules.card(UnoRules.CardColor.RED, 5))
	var duel_moves := duel.generate_moves(heads_up)
	_equals(duel_moves.size(), 2, "numa mesa de dois o 7 dá um lance só")
	_equals(UnoRules.target_of(duel_moves[0]), 1, "com o alvo já resolvido")

	# O 0 roda a mesa no sentido do jogo: cada um recebe a mão de quem joga antes.
	var zero := UnoRules.card(UnoRules.CardColor.RED, 0)
	var rotate := _rig(4, true, [
		[zero, UnoRules.card(UnoRules.CardColor.BLUE, 1)],
		[UnoRules.card(UnoRules.CardColor.BLUE, 2)],
		[UnoRules.card(UnoRules.CardColor.BLUE, 3)],
		[UnoRules.card(UnoRules.CardColor.BLUE, 4)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	_rules.apply_move(rotate, _find(rotate, zero))
	_equals(
		UnoRules.hand_of(rotate, 1), PackedInt32Array([UnoRules.card(UnoRules.CardColor.BLUE, 1)]),
		"o 0 passa a mão de cada um para quem joga depois"
	)
	_equals(
		UnoRules.hand_of(rotate, 0), PackedInt32Array([UnoRules.card(UnoRules.CardColor.BLUE, 4)]),
		"e quem jogou recebe a de quem joga antes"
	)

	# Com o sentido invertido, as mãos andam para o outro lado junto.
	var backward := _rig(4, true, [
		[zero, UnoRules.card(UnoRules.CardColor.BLUE, 1)],
		[UnoRules.card(UnoRules.CardColor.BLUE, 2)],
		[UnoRules.card(UnoRules.CardColor.BLUE, 3)],
		[UnoRules.card(UnoRules.CardColor.BLUE, 4)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	backward.meta[UnoRules.DIR] = -1
	_rules.apply_move(backward, _find(backward, zero))
	_equals(
		UnoRules.hand_of(backward, 3), PackedInt32Array([UnoRules.card(UnoRules.CardColor.BLUE, 1)]),
		"com o sentido invertido a rotação acompanha"
	)

	# Duas rotações numa mesa de quatro **não** devolvem a mesa ao ponto de
	# partida. É o teste que pega a rotação que compartilha buffer: com as chaves
	# apontando para o mesmo vetor, todas as mãos viram a mesma e uma rotação a
	# mais não muda nada.
	var twice := _rig(4, true, [
		[UnoRules.card(UnoRules.CardColor.BLUE, 1)],
		[UnoRules.card(UnoRules.CardColor.BLUE, 2)],
		[UnoRules.card(UnoRules.CardColor.BLUE, 3)],
		[UnoRules.card(UnoRules.CardColor.BLUE, 4)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	UnoRules._rotate_hands(twice)
	UnoRules._rotate_hands(twice)
	_equals(
		UnoRules.hand_of(twice, 0), PackedInt32Array([UnoRules.card(UnoRules.CardColor.BLUE, 3)]),
		"duas rotações numa mesa de quatro andam duas casas, não zero"
	)
	var distinct := {}
	for seat in 4:
		distinct[UnoRules.hand_of(twice, seat)] = true
	_equals(distinct.size(), 4, "e as quatro mãos continuam diferentes entre si")


## A armadilha do `clone()` raso: uma variante explorada em cima da cópia não pode
## mexer na partida de verdade.
##
## O `clone()` duplica os `Packed*Array` de `meta` chave por chave, mas isso
## acontece **antes** de qualquer troca de mãos. Uma rotação que só reatribuísse
## referências deixaria a cópia e o original compartilhando vetores, e o efeito
## aparece sem nada falhar — que é como este arquivo erra.
func _probe_clone_isolation() -> void:
	print("isolamento da cópia")
	var zero := UnoRules.card(UnoRules.CardColor.RED, 0)
	var state := _rig(4, true, [
		[zero, UnoRules.card(UnoRules.CardColor.BLUE, 1)],
		[UnoRules.card(UnoRules.CardColor.BLUE, 2)],
		[UnoRules.card(UnoRules.CardColor.BLUE, 3)],
		[UnoRules.card(UnoRules.CardColor.BLUE, 4)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))

	var before := []
	for seat in 4:
		before.append(UnoRules.hand_of(state, seat))

	var probe := state.clone()
	_rules.apply_move(probe, _find(probe, zero))

	for seat in 4:
		_equals(
			UnoRules.hand_of(state, seat), before[seat],
			"rodar as mãos na cópia não mexe na do assento %d no original" % seat
		)

	# O mesmo para o 7, que é a outra porta.
	var seven := UnoRules.card(UnoRules.CardColor.RED, 7)
	var swap := _rig(4, true, [
		[seven, UnoRules.card(UnoRules.CardColor.BLUE, 1)],
		[UnoRules.card(UnoRules.CardColor.GREEN, 2)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	var mine := UnoRules.hand_of(swap, 0)
	var theirs := UnoRules.hand_of(swap, 1)
	var copy := swap.clone()
	_rules.apply_move(copy, _find_target(copy, seven, 1))
	_equals(UnoRules.hand_of(swap, 0), mine, "trocar na cópia não mexe na mão de quem jogou")
	_equals(UnoRules.hand_of(swap, 1), theirs, "nem na do alvo")


## A última carta vence, e o efeito dela não acontece.
##
## Sem isso, um 7 jogado como última carta trocaria a mão vazia do vencedor por
## uma cheia e desfaria a vitória que acabou de acontecer.
func _probe_last_card() -> void:
	print("última carta")
	var seven := UnoRules.card(UnoRules.CardColor.RED, 7)
	var state := _rig(4, true, [
		[seven],
		[UnoRules.card(UnoRules.CardColor.GREEN, 2), UnoRules.card(UnoRules.CardColor.GREEN, 3)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	_rules.apply_move(state, _find_target(state, seven, 1))
	_equals(_rules.winner(state), 0, "quem esvaziou a mão venceu")
	_equals(UnoRules.hand_size(state, 0), 0, "e a mão dele continua vazia")
	_equals(UnoRules.hand_size(state, 1), 2, "o alvo ficou com a dele")
	_equals(_rules.generate_moves(state).size(), 0, "e acabou a partida")

	var zero := UnoRules.card(UnoRules.CardColor.RED, 0)
	var rotated := _rig(4, true, [
		[zero],
		[UnoRules.card(UnoRules.CardColor.GREEN, 2)],
		[UnoRules.card(UnoRules.CardColor.GREEN, 3)],
		[UnoRules.card(UnoRules.CardColor.GREEN, 4)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	_rules.apply_move(rotated, _find(rotated, zero))
	_equals(_rules.winner(rotated), 0, "o mesmo vale para o 0")
	_equals(UnoRules.hand_size(rotated, 1), 1, "e a mesa não rodou")


## O monte que acaba é refeito do descarte, pelo mesmo gerador — e a carta virada
## fica onde está.
func _probe_reshuffle() -> void:
	print("rembaralho")
	var state := _rig(4, true, [
		[UnoRules.card(UnoRules.CardColor.BLUE, 9)],
	], UnoRules.card(UnoRules.CardColor.RED, 5))
	state.meta[UnoRules.DECK] = PackedInt32Array()
	var pile := PackedInt32Array()
	for value in range(1, 10):
		pile.append(UnoRules.card(UnoRules.CardColor.GREEN, value))
	pile.append(UnoRules.card(UnoRules.CardColor.RED, 5))
	state.meta[UnoRules.PILE] = pile

	var twin := state.clone()
	twin.meta[UnoRules.PILE] = pile

	_rules.apply_move(state, _find_kind(state, UnoRules.DRAW))
	_equals(UnoRules.pile_of(state).size(), 1, "o descarte fica só com a carta virada")
	_equals(
		UnoRules.top_card(state), UnoRules.card(UnoRules.CardColor.RED, 5),
		"e ela continua sendo a mesma"
	)
	_equals(UnoRules.deck_of(state).size(), 8, "o resto volta para o monte, menos a comprada")

	# O mesmo estado, refeito duas vezes, dá o mesmo monte. É o que impede os N
	# aparelhos de divergirem no meio de uma partida longa.
	_rules.apply_move(twin, _find_kind(twin, UnoRules.DRAW))
	_equals(
		UnoRules.deck_of(twin), UnoRules.deck_of(state),
		"e o rembaralho é o mesmo nos dois aparelhos"
	)


## O histórico reproduz a partida: é o que a reconexão repete, e é o único
## caminho pelo qual uma mão oculta chega a quem entrou no meio.
func _probe_replay() -> void:
	print("histórico")
	var played := _make(4, true).initial_state()
	for _turn in 40:
		if _rules.winner(played) >= 0:
			break
		var moves := _rules.generate_moves(played)
		if moves.is_empty():
			_failures += 1
			printerr("  FAIL nenhum lance possível no lance %d" % played.ply)
			return
		_rules.apply_move(played, moves[0])

	var replayed := _make(4, true).initial_state()
	for data in played.history:
		_rules.apply_move(replayed, Move.from_dict(data))

	for seat in 4:
		_equals(
			UnoRules.hand_of(replayed, seat), UnoRules.hand_of(played, seat),
			"repetir o histórico devolve a mão do assento %d" % seat
		)
	_equals(UnoRules.deck_of(replayed), UnoRules.deck_of(played), "e o mesmo monte")
	_equals(UnoRules.turn_of(replayed), UnoRules.turn_of(played), "e a mesma vez")
	_equals(UnoRules.active_color(replayed), UnoRules.active_color(played), "e a mesma cor ativa")

	# O mesmo histórico sob a regra da casa invertida **não** reproduz a partida.
	# É a prova de que a regra viaja de verdade em vez de ser enfeite local.
	var flipped := _make(4, false).initial_state()
	var diverged := false
	for data in played.history:
		var move := Move.from_dict(data)
		if move.path.size() != UnoRules.PATH_SIZE:
			diverged = true
			break
		var legal := false
		for candidate in _make(4, false).generate_moves(flipped):
			if candidate.path == move.path:
				legal = true
				break
		if not legal:
			diverged = true
			break
		_make(4, false).apply_move(flipped, move)
	_check(diverged, "o mesmo histórico sob a regra invertida é recusado")


func _probe_option() -> void:
	print("semente e regra no `option`")
	Game.uno_sevens = true
	var on := Game.host_option(Game.UNO)
	_check(Game.uno_sevens_of(on), "ligada, a bandeira viaja ligada")
	_check(Game.uno_seed_of(on) != 0, "e a semente nunca é zero")

	Game.uno_sevens = false
	var off := Game.host_option(Game.UNO)
	_check(not Game.uno_sevens_of(off), "desligada, viaja desligada")
	_check(Game.uno_seed_of(off) != 0, "e a semente continua não sendo zero")

	# A bandeira não pode contaminar a semente: dois `option` que só diferem no bit
	# 30 têm de dar o mesmo baralho.
	var seed := 12345678
	_equals(
		Game.uno_seed_of(seed | Game.UNO_SEVENS_BIT), Game.uno_seed_of(seed),
		"a bandeira não mexe na semente"
	)
	# E o campo continua servindo aos outros jogos.
	Game.round_limit = 20
	_equals(Game.host_option(Game.MONOPOLY), 20, "Metrópole continua mandando as rodadas")
	_check(Game.host_option(Game.CHESS) == 0, "e o xadrez não manda nada")


## Uma mesa de bots jogando até o fim.
##
## O que se verifica não é a qualidade do jogo — é que a partida **termina** e que
## a heurística sempre tem o que responder. Um `null` aqui trava a vez para
## sempre, e é uma travada que só aparece depois de dezenas de lances, no
## aparelho, com quatro pessoas esperando.
func _probe_bot() -> void:
	print("bot")
	for sevens in [true, false]:
		var rules := _make(4, sevens)
		var state := rules.initial_state()
		var plays := 0
		var limit := 4000
		while rules.winner(state) < 0 and plays < limit:
			var moves := rules.generate_moves(state)
			if moves.is_empty():
				_failures += 1
				printerr("  FAIL nenhum lance no lance %d (regra da casa: %s)" % [plays, sevens])
				return
			var choice := rules.best_move(state, moves)
			if choice == null:
				_failures += 1
				printerr("  FAIL a heurística não escolheu entre %d lances" % moves.size())
				return
			rules.apply_move(state, choice)
			plays += 1

		var label := "com a regra da casa" if sevens else "sem ela"
		_check(plays < limit, "a partida entre bots termina %s (%d lances)" % [label, plays])
		_check(rules.winner(state) >= 0, "e alguém vence %s" % label)

		var replayed := _make(4, sevens).initial_state()
		for data in state.history:
			replayed_apply(rules, replayed, data)
		_equals(
			UnoRules.hand_of(replayed, 0), UnoRules.hand_of(state, 0),
			"e repetir o histórico do bot devolve a mesma mão %s" % label
		)


func replayed_apply(rules: UnoRules, state: MatchState, data: Dictionary) -> void:
	rules.apply_move(state, Move.from_dict(data))


# --- utilidades ---------------------------------------------------------------


## Um estado com as mãos escritas à mão, para os testes que precisam de uma
## posição exata em vez de uma sorteada.
##
## O monte fica cheio de cartas que não servem, para que comprar não resolva a
## posição por acidente — os testes de compra escrevem o deles por cima.
func _rig(seats: int, sevens: bool, hands: Array, top: int) -> MatchState:
	var state := MatchState.new()
	state.meta[UnoRules.SEATS] = seats
	state.meta[UnoRules.SEVENS] = 1 if sevens else 0
	state.meta[UnoRules.RNG] = SEED
	state.meta[UnoRules.TURN] = 0
	state.meta[UnoRules.DIR] = 1
	state.meta[UnoRules.DREW] = 0
	state.meta[UnoRules.PILE] = PackedInt32Array([top])
	state.meta[UnoRules.COLOR] = UnoRules.color_of_card(top)

	var deck := PackedInt32Array()
	for _each in 20:
		deck.append(UnoRules.card(UnoRules.CardColor.YELLOW, 8))
	state.meta[UnoRules.DECK] = deck

	for seat in seats:
		var hand := PackedInt32Array()
		if seat < hands.size():
			for card in hands[seat]:
				hand.append(int(card))
		if hand.is_empty():
			# Mão vazia é vitória, e um assento vazio por descuido acabaria a
			# partida antes de o teste começar.
			hand.append(UnoRules.card(UnoRules.CardColor.YELLOW, 8))
		state.meta[UnoRules.hand_key(seat)] = hand
	return state


func _find(state: MatchState, card: int) -> Move:
	return _find_with(_rules, state, card)


func _find_with(rules: UnoRules, state: MatchState, card: int) -> Move:
	for move in rules.generate_moves(state):
		if UnoRules.kind_of(move) == UnoRules.PLAY and UnoRules.card_of(move) == card:
			return move
	return null


func _find_colored(state: MatchState, card: int, color: int) -> Move:
	for move in _rules.generate_moves(state):
		if UnoRules.card_of(move) == card and UnoRules.declared_color(move) == color:
			return move
	return null


func _find_target(state: MatchState, card: int, target: int) -> Move:
	for move in _rules.generate_moves(state):
		if UnoRules.card_of(move) == card and UnoRules.target_of(move) == target:
			return move
	return null


func _find_kind(state: MatchState, kind: int) -> Move:
	for move in _rules.generate_moves(state):
		if UnoRules.kind_of(move) == kind:
			return move
	return null


func _equals(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s (esperado %s, obtido %s)" % [label, expected, actual])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		printerr("  FAIL %s" % label)
