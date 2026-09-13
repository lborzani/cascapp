extends SceneTree

## Regras de Metrópole, sem tela.
##
##   godot --headless --path . --import
##   godot --headless --path . --script res://tests/monopoly_probe.gd
##
## Este jogo erra em silêncio em três lugares, e os três estão cobertos aqui.
##
## **A máquina de fases.** Um turno são vários lances, e a fase é quem diz qual
## lance é legal agora. Uma transição errada não trava nada visível — ela deixa
## um jogador rolar duas vezes, ou some com a chance de comprar. Por isso o teste
## principal é uma partida inteira jogada ao acaso com semente fixa: se alguma
## fase levar a uma lista de lances vazia sem a partida ter acabado, o jogo
## travou, e é aqui que isso aparece.
##
## **A cópia rasa de `meta`.** Sete `PackedInt32Array` num dicionário copiado
## raso funcionam porque `PackedInt32Array` é cópia-na-escrita. Se um dia alguém
## trocar um deles por `Array`, nada quebra na hora: o bot passa a corromper a
## partida ao explorar variantes, meses depois, sem mensagem nenhuma. O teste do
## clone é a única coisa que pega isso.
##
## **O replay.** Repetir `history` tem de devolver `meta` idêntico, porque é
## exatamente isso que a reconexão faz. Os dois acasos — dados e carta — moram
## dentro do lance justamente para isto valer.

const Rules := preload("res://core/monopoly_rules.gd")
const BoardData := preload("res://core/monopoly_board.gd")

var _failures := 0
var _rules: MonopolyRules = null


func _initialize() -> void:
	_rules = Rules.new()
	_probe_board()
	_probe_movement()
	_probe_rent()
	_probe_building()
	_probe_jail()
	_probe_debt()
	_probe_bankruptcy()
	_probe_trade()
	_probe_clone()
	_probe_geometry()
	_probe_walk()
	_probe_playout()
	_probe_bot()
	_probe_replay()

	if _failures == 0:
		print("OK — regras de Metrópole consistentes.")
	else:
		printerr("%d teste(s) falharam." % _failures)
	quit(1 if _failures > 0 else 0)


# --- tabuleiro ----------------------------------------------------------------


func _probe_board() -> void:
	print("tabuleiro")
	_equals(BoardData.TILES.size(), BoardData.SIZE, "quarenta casas")
	_equals(
		BoardData.kind_of(BoardData.JAIL_TILE), BoardData.Tile.JAIL,
		"a cadeia está na casa 10"
	)
	_equals(
		BoardData.kind_of(BoardData.GOTO_JAIL_TILE), BoardData.Tile.GOTO_JAIL,
		"e o 'vá para a cadeia' na 30, na diagonal oposta"
	)

	var deeds := 0
	var colours := 0
	for tile in BoardData.SIZE:
		if BoardData.is_deed(tile):
			deeds += 1
		if BoardData.can_build_on(tile):
			colours += 1
	_equals(deeds, 28, "vinte e oito casas têm dono")
	_equals(colours, 22, "vinte e duas delas constroem")
	_equals(
		BoardData.group_tiles(BoardData.Group.AIRPORTS).size(), 4, "quatro aeroportos"
	)
	_equals(
		BoardData.group_tiles(BoardData.Group.UTILITIES).size(), 2, "duas companhias"
	)

	# Os oito grupos de cor: dois de dois e seis de três. Um grupo com o tamanho
	# errado quebra o aluguel dobrado e a construção uniforme ao mesmo tempo, e
	# nenhum dos dois avisa.
	var sizes := PackedInt32Array()
	for group in range(BoardData.Group.BROWN, BoardData.Group.AIRPORTS):
		sizes.append(BoardData.group_tiles(group).size())
	_equals(Array(sizes), [2, 3, 3, 3, 3, 3, 3, 2], "os oito grupos têm o tamanho clássico")

	# Toda casa de cor tem seis degraus de aluguel e um preço de construção. Um
	# `rent` curto só estoura quando alguém chega ao hotel, o que pode levar uma
	# hora de partida.
	for tile in BoardData.SIZE:
		if not BoardData.can_build_on(tile):
			continue
		var table: Array = BoardData.tile(tile)["rent"]
		if table.size() != 6:
			_fail("casa %d tem %d degraus de aluguel, não 6" % [tile, table.size()])
		if BoardData.house_cost(tile) <= 0:
			_fail("casa %d não tem preço de construção" % tile)

	# As duas cartas de saída livre, uma por baralho. `meta["jc"]` guarda isso em
	# dois bits e assume exatamente uma de cada lado.
	for deck in [BoardData.CHANCE, BoardData.CHEST]:
		var free := 0
		for card in BoardData.deck(deck):
			if int(card["effect"]) == BoardData.Effect.JAIL_CARD:
				free += 1
		_equals(free, 1, "o baralho %d tem uma carta de saída livre" % deck)


# --- percurso -----------------------------------------------------------------


func _probe_movement() -> void:
	print("percurso e salário")
	var state := _fresh(2)
	_place(state, 0, 38)
	var before := MonopolyRules.cash_of(state, 0)
	_apply(state, [MonopolyRules.Act.ROLL, 2, 1])
	_equals(MonopolyRules.position_of(state, 0), 1, "dar a volta continua da casa 1")
	_equals(
		MonopolyRules.cash_of(state, 0) - before, BoardData.GO_SALARY,
		"e cruzar a Partida paga o salário"
	)

	# Três duplas seguidas mandam para a cadeia sem andar — é a regra que impede
	# o turno infinito, e o peão **não** passa pela Partida no caminho.
	state = _fresh(2)
	_place(state, 0, 35)
	var cash := MonopolyRules.cash_of(state, 0)
	_apply(state, [MonopolyRules.Act.ROLL, 1, 1])
	_apply(state, [MonopolyRules.Act.END, 0, 0])
	_apply(state, [MonopolyRules.Act.ROLL, 1, 1])
	_apply(state, [MonopolyRules.Act.END, 0, 0])
	_apply(state, [MonopolyRules.Act.ROLL, 1, 1])
	_equals(
		MonopolyRules.position_of(state, 0), BoardData.JAIL_TILE,
		"a terceira dupla seguida termina na cadeia"
	)
	_equals(MonopolyRules.jail_of(state, 0), 0, "e o jogador fica preso")
	_equals(
		MonopolyRules.cash_of(state, 0), cash,
		"sem passar pela Partida, apesar de as três duplas darem a volta"
	)

	# A casa 30 manda para a cadeia. É o único caso em que andar para a frente
	# termina 20 casas atrás.
	state = _fresh(2)
	_place(state, 0, 28)
	_apply(state, [MonopolyRules.Act.ROLL, 1, 1])
	_equals(
		MonopolyRules.position_of(state, 0), BoardData.JAIL_TILE,
		"parar na casa 30 vai para a cadeia"
	)


# --- aluguel ------------------------------------------------------------------


func _probe_rent() -> void:
	print("aluguel")
	var state := _fresh(2)
	# Guamá e Icoaraci, o grupo marrom.
	var first := 1
	var second := 3
	_own(state, first, 1)
	_equals(
		MonopolyRules.rent_for(state, first, 7), 2,
		"terreno solto cobra o primeiro degrau"
	)
	_own(state, second, 1)
	_equals(
		MonopolyRules.rent_for(state, first, 7), 4,
		"fechar a cor dobra o aluguel do terreno vazio"
	)

	state.meta[MonopolyRules.HOUSES][first] = 1
	_equals(
		MonopolyRules.rent_for(state, first, 7), 10,
		"e a primeira casa sobe para o segundo degrau, sem dobrar de novo"
	)
	state.meta[MonopolyRules.HOUSES][first] = BoardData.HOTEL
	_equals(MonopolyRules.rent_for(state, first, 7), 250, "hotel é o sexto degrau")

	state.meta[MonopolyRules.MORT][first] = 1
	_equals(
		MonopolyRules.rent_for(state, first, 7), 0,
		"casa hipotecada não cobra nada, mesmo com hotel"
	)

	# Aeroporto cobra por quantidade, e a escala dobra a cada um.
	state = _fresh(2)
	var airports := BoardData.group_tiles(BoardData.Group.AIRPORTS)
	for count in range(1, 5):
		_own(state, airports[count - 1], 1)
		_equals(
			MonopolyRules.rent_for(state, airports[0], 7),
			int(BoardData.AIRPORT_RENT[count - 1]),
			"com %d aeroporto(s) o aluguel é %d" % [count, BoardData.AIRPORT_RENT[count - 1]]
		)

	# Companhia é o único aluguel do jogo que depende do dado.
	state = _fresh(2)
	var utilities := BoardData.group_tiles(BoardData.Group.UTILITIES)
	_own(state, utilities[0], 1)
	_equals(MonopolyRules.rent_for(state, utilities[0], 9), 36, "uma companhia cobra 4x a rolagem")
	_own(state, utilities[1], 1)
	_equals(MonopolyRules.rent_for(state, utilities[0], 9), 90, "as duas cobram 10x")

	# E o dono não paga a si mesmo.
	state = _fresh(2)
	_own(state, 1, 0)
	_place(state, 0, 39)
	_apply(state, [MonopolyRules.Act.ROLL, 1, 1])
	_equals(
		MonopolyRules.phase_of(state), MonopolyRules.Phase.MANAGE,
		"parar na própria casa não cobra nada"
	)


# --- construção ---------------------------------------------------------------


func _probe_building() -> void:
	print("construção")
	var state := _fresh(2)
	var first := 1
	var second := 3
	_own(state, first, 0)
	_equals(
		_can(state, [MonopolyRules.Act.BUILD, first]), false,
		"não se constrói sem a cor fechada"
	)

	_own(state, second, 0)
	_equals(_can(state, [MonopolyRules.Act.BUILD, first]), true, "com a cor fechada, sim")
	_apply(state, [MonopolyRules.Act.BUILD, first])
	_equals(MonopolyRules.houses_on(state, first), 1, "a casa sobe")
	_equals(
		_can(state, [MonopolyRules.Act.BUILD, first]), false,
		"a segunda casa aqui só depois de a irmã ter a primeira"
	)
	_equals(
		_can(state, [MonopolyRules.Act.BUILD, second]), true,
		"e é a irmã que está disponível"
	)

	# Vender é o espelho: sai a construção mais alta primeiro.
	_equals(_can(state, [MonopolyRules.Act.SELL, first]), true, "vende-se a mais alta")
	_equals(
		_can(state, [MonopolyRules.Act.SELL, second]), false,
		"e não a que não tem construção nenhuma"
	)

	# Hipoteca exige o grupo limpo, e grupo com hipoteca não constrói.
	_equals(
		_can(state, [MonopolyRules.Act.MORTGAGE, second]), false,
		"não se hipoteca um grupo em obras, nem a casa vazia dele"
	)
	_apply(state, [MonopolyRules.Act.SELL, first])
	_equals(
		_can(state, [MonopolyRules.Act.MORTGAGE, second]), true,
		"desfeitas as obras, a hipoteca libera"
	)
	_apply(state, [MonopolyRules.Act.MORTGAGE, second])
	_equals(
		_can(state, [MonopolyRules.Act.BUILD, first]), false,
		"e com metade do grupo no banco não se constrói na outra metade"
	)

	# Resgatar custa a hipoteca mais 10%.
	_equals(
		BoardData.unmortgage_cost(second), 33,
		"resgatar 30 de hipoteca custa 33"
	)

	# Teto no hotel: seis degraus, não sete.
	state = _fresh(2)
	_own(state, first, 0)
	_own(state, second, 0)
	state.meta[MonopolyRules.HOUSES][first] = BoardData.HOTEL
	state.meta[MonopolyRules.HOUSES][second] = BoardData.HOTEL
	_equals(
		_can(state, [MonopolyRules.Act.BUILD, first]), false,
		"depois do hotel não há mais degrau"
	)


# --- cadeia -------------------------------------------------------------------


func _probe_jail() -> void:
	print("cadeia")
	var state := _fresh(2)
	_jail(state, 0)
	_equals(
		MonopolyRules.phase_of(state), MonopolyRules.Phase.JAILED,
		"o turno de quem está preso começa na fase da cadeia"
	)
	_equals(_can(state, [MonopolyRules.Act.BAIL]), true, "pagar fiança é opção")

	# Dupla solta e anda, mas não dá turno extra.
	_apply(state, [MonopolyRules.Act.ROLL, 2, 2])
	_equals(MonopolyRules.in_jail(state, 0), false, "a dupla solta")
	_equals(
		MonopolyRules.position_of(state, 0), BoardData.JAIL_TILE + 4,
		"e o peão anda a soma"
	)
	_apply(state, [MonopolyRules.Act.END, 0, 0])
	_equals(MonopolyRules.turn_of(state), 1, "sair com dupla não devolve o turno")

	# Três tentativas fracassadas: paga a fiança e anda.
	state = _fresh(2)
	_jail(state, 0)
	var cash := MonopolyRules.cash_of(state, 0)
	for attempt in 2:
		_apply(state, [MonopolyRules.Act.ROLL, 1, 2])
		_equals(MonopolyRules.in_jail(state, 0), true, "a tentativa %d não solta" % (attempt + 1))
		_apply(state, [MonopolyRules.Act.END, 0, 0])
		_apply(state, [MonopolyRules.Act.ROLL, 1, 2])
		_apply(state, [MonopolyRules.Act.END, 0, 0])
	_apply(state, [MonopolyRules.Act.ROLL, 1, 2])
	_equals(MonopolyRules.in_jail(state, 0), false, "a terceira tentativa solta de qualquer jeito")
	_equals(
		MonopolyRules.cash_of(state, 0) - cash, -BoardData.BAIL,
		"cobrando a fiança"
	)
	_equals(
		MonopolyRules.position_of(state, 0), BoardData.JAIL_TILE + 3,
		"e o peão anda a rolagem que não deu dupla"
	)

	# A carta de saída livre sai do baralho enquanto está na mão.
	state = _fresh(2)
	var index := _card_index(BoardData.CHANCE, BoardData.Effect.JAIL_CARD)
	_place(state, 0, 7)
	_apply(state, [MonopolyRules.Act.ROLL, 0, 0])
	_equals(MonopolyRules.phase_of(state), MonopolyRules.Phase.DRAW, "Sorte pede uma carta")
	_apply(state, [MonopolyRules.Act.DRAW, BoardData.CHANCE, index])
	_equals(MonopolyRules.jail_cards_of(state, 0), 1, "a carta fica na mão")
	_equals(
		_can(state, [MonopolyRules.Act.DRAW, BoardData.CHANCE, index]), false,
		"e some do baralho enquanto estiver lá"
	)


# --- dívida -------------------------------------------------------------------


func _probe_debt() -> void:
	print("dívida e fase de levantar dinheiro")
	var state := _fresh(2)
	# Jogador 1 é dono do Leblon com hotel; jogador 0 cai lá com pouco no bolso.
	_own(state, 37, 1)
	state.meta[MonopolyRules.HOUSES][37] = BoardData.HOTEL
	_set_cash(state, 0, 100)
	_own(state, 5, 0)
	_place(state, 0, 35)
	_apply(state, [MonopolyRules.Act.ROLL, 1, 1])

	_equals(
		MonopolyRules.phase_of(state), MonopolyRules.Phase.RAISE,
		"aluguel maior que o caixa abre a fase de levantar dinheiro"
	)
	_equals(MonopolyRules.debt_of(state), 1500, "a dívida é o aluguel do hotel")
	_equals(MonopolyRules.creditor_of(state), 1, "e o credor é o dono")
	_equals(
		_can(state, [MonopolyRules.Act.END, 0, 0]), false,
		"e não se encerra o turno devendo"
	)
	_equals(
		_can(state, [MonopolyRules.Act.BANKRUPT]), true,
		"quebrar é sempre uma saída"
	)

	# Hipotecar o aeroporto rende 100 — ainda não cobre, e a fase não muda.
	_apply(state, [MonopolyRules.Act.MORTGAGE, 5])
	_equals(
		MonopolyRules.phase_of(state), MonopolyRules.Phase.RAISE,
		"levantar pouco não sai da fase"
	)

	# Injetar o resto e vender qualquer coisa fecha a conta.
	_set_cash(state, 0, 1500)
	var landlord := MonopolyRules.cash_of(state, 1)
	_own(state, 15, 0)
	_apply(state, [MonopolyRules.Act.MORTGAGE, 15])
	_equals(
		MonopolyRules.phase_of(state), MonopolyRules.Phase.MANAGE,
		"coberta a dívida, o turno volta a andar"
	)
	_equals(MonopolyRules.debt_of(state), 0, "e a dívida zera")
	_equals(
		MonopolyRules.cash_of(state, 1) - landlord, 1500,
		"o credor recebe o que era devido"
	)


func _probe_bankruptcy() -> void:
	print("falência")
	var state := _fresh(3)
	_own(state, 1, 0)
	_own(state, 3, 0)
	state.meta[MonopolyRules.HOUSES][1] = 2
	_own(state, 39, 1)
	state.meta[MonopolyRules.HOUSES][39] = BoardData.HOTEL
	_set_cash(state, 0, 0)
	_place(state, 0, 37)
	_apply(state, [MonopolyRules.Act.ROLL, 1, 1])
	_equals(MonopolyRules.phase_of(state), MonopolyRules.Phase.RAISE, "dívida impagável")

	var creditor := MonopolyRules.cash_of(state, 1)
	_apply(state, [MonopolyRules.Act.BANKRUPT])
	_equals(MonopolyRules.is_out(state, 0), true, "quem quebra sai da partida")
	_equals(MonopolyRules.owner_of(state, 1), 1, "as escrituras passam ao credor")
	_equals(MonopolyRules.owner_of(state, 3), 1, "todas elas")
	_equals(MonopolyRules.houses_on(state, 1), 0, "as construções voltam ao banco")
	_equals(
		MonopolyRules.cash_of(state, 1) - creditor, 50,
		"e o credor recebe metade do que foi gasto construindo"
	)
	_equals(MonopolyRules.turn_of(state), 1, "o turno segue para o próximo vivo")

	# Sobrando um, acabou.
	_equals(_rules.winner(state), -1, "com dois vivos ainda não há vencedor")
	state.meta[MonopolyRules.OUT][1] = 1
	_equals(_rules.winner(state), 2, "sobrando um, ele venceu")

	# Modo curto: fechadas as rodadas, vence o patrimônio.
	var short_game := _fresh(2, 3)
	_set_cash(short_game, 1, 5000)
	short_game.meta[MonopolyRules.ROUND] = 3
	_equals(_rules.winner(short_game), 1, "no modo por rodadas vence o maior patrimônio")


# --- troca --------------------------------------------------------------------


## A troca é o único lance que `generate_moves` não enumera, então é o único cuja
## legalidade não é conferida por pertencer a uma lista. Toda a proteção mora em
## `validate()` — e o que não estiver testado aqui não está testado em lugar
## nenhum.
##
## O que se confere é o que um cliente modificado tentaria: dar o que não é seu,
## pedir o que o outro não tem, pagar dinheiro que não existe, e propor no meio de
## um momento em que a partida está esperando outra resposta. Em rede isso não é
## hipótese — é a única barreira entre o outro aparelho e o tabuleiro daqui.
func _probe_trade() -> void:
	print("troca entre jogadores")

	# A codificação, de ida e volta. Ela é o formato de fio da troca, e um lado
	# lendo o caminho diferente do outro é uma partida que diverge em silêncio.
	var path := MonopolyRules.offer_path(
		2, -150, PackedInt32Array([1, 3]), PackedInt32Array([6])
	)
	_equals(
		str(MonopolyRules.offered_give(path)), str(PackedInt32Array([1, 3])),
		"o caminho da proposta devolve o que sai"
	)
	_equals(
		str(MonopolyRules.offered_get(path)), str(PackedInt32Array([6])),
		"e o que entra"
	)

	var state := _fresh(4)
	state.meta[MonopolyRules.PHASE] = MonopolyRules.Phase.MANAGE
	_own(state, 1, 0)
	_own(state, 3, 0)
	_own(state, 6, 1)
	_set_cash(state, 0, 500)
	_set_cash(state, 1, 500)

	# Rua por rua mais dinheiro: o jogador 0 dá a 1 e a 3, recebe a 6 e 100.
	var deal := MonopolyRules.offer_path(
		1, -100, PackedInt32Array([1, 3]), PackedInt32Array([6])
	)
	_equals(_rules.validate(state, deal) != null, true, "a proposta bem montada é aceita pelas regras")

	# --- o que não pode --------------------------------------------------------
	_equals(
		_rules.validate(state, MonopolyRules.offer_path(
			1, 0, PackedInt32Array([6]), PackedInt32Array()
		)) == null, true, "não dá para oferecer o que é do outro"
	)
	_equals(
		_rules.validate(state, MonopolyRules.offer_path(
			1, 0, PackedInt32Array(), PackedInt32Array([9])
		)) == null, true, "nem pedir o que não é dele"
	)
	_equals(
		_rules.validate(state, MonopolyRules.offer_path(
			1, 900, PackedInt32Array(), PackedInt32Array([6])
		)) == null, true, "nem pagar dinheiro que não se tem"
	)
	_equals(
		_rules.validate(state, MonopolyRules.offer_path(
			1, -900, PackedInt32Array([1]), PackedInt32Array()
		)) == null, true, "nem cobrar o que o outro não tem"
	)
	_equals(
		_rules.validate(state, MonopolyRules.offer_path(
			0, 50, PackedInt32Array(), PackedInt32Array()
		)) == null, true, "nem propor para si mesmo"
	)
	_equals(
		_rules.validate(state, MonopolyRules.offer_path(
			1, 0, PackedInt32Array(), PackedInt32Array()
		)) == null, true, "nem propor nada em troca de nada"
	)
	_equals(
		_rules.validate(state, MonopolyRules.offer_path(
			1, 50, PackedInt32Array([1, 1]), PackedInt32Array()
		)) == null, true, "nem oferecer a mesma casa duas vezes"
	)

	# Grupo com obra não sai da mão: a irmã construída ficaria de pé num grupo de
	# dois donos, e a regra de uniformidade não sabe desfazer isso.
	state.meta[MonopolyRules.HOUSES][3] = 1
	_equals(
		_rules.validate(state, MonopolyRules.offer_path(
			1, 0, PackedInt32Array([1]), PackedInt32Array()
		)) == null, true, "nem trocar uma casa cujo grupo tem construção"
	)
	state.meta[MonopolyRules.HOUSES][3] = 0

	state.meta[MonopolyRules.PHASE] = MonopolyRules.Phase.DRAW
	_equals(
		_rules.validate(state, deal) == null, true,
		"nem propor com uma carta por virar"
	)
	state.meta[MonopolyRules.PHASE] = MonopolyRules.Phase.MANAGE

	# --- recusar não custa nada ------------------------------------------------
	_apply(state, Array(deal))
	_equals(MonopolyRules.phase_of(state), MonopolyRules.Phase.TRADE, "a proposta na mesa muda a fase")
	_equals(MonopolyRules.actor_of(state), 1, "e quem responde é o destinatário, não o da vez")
	_equals(MonopolyRules.turn_of(state), 0, "a vez continua sendo de quem propôs")
	_equals(_can(state, [MonopolyRules.Act.ROLL, 3, 4]), false, "que não pode fazer mais nada")

	_apply(state, [MonopolyRules.Act.REJECT])
	_equals(MonopolyRules.phase_of(state), MonopolyRules.Phase.MANAGE, "recusada, a fase volta ao que era")
	_equals(MonopolyRules.owner_of(state, 1), 0, "e nada mudou de mão")
	_equals(MonopolyRules.cash_of(state, 0), 500, "nem de caixa")

	# --- aceitar move tudo de uma vez ------------------------------------------
	_apply(state, Array(deal))
	_apply(state, [MonopolyRules.Act.ACCEPT])
	_equals(MonopolyRules.owner_of(state, 1), 1, "aceita, a escritura oferecida muda de dono")
	_equals(MonopolyRules.owner_of(state, 3), 1, "as duas")
	_equals(MonopolyRules.owner_of(state, 6), 0, "e a pedida vem para cá")
	_equals(MonopolyRules.cash_of(state, 0), 600, "o dinheiro cobrado entra")
	_equals(MonopolyRules.cash_of(state, 1), 400, "e sai de quem aceitou")
	_equals(MonopolyRules.phase_of(state), MonopolyRules.Phase.MANAGE, "e o turno segue de onde parou")

	# --- a hipoteca viaja junto ------------------------------------------------
	var mortgaged := _fresh(2)
	mortgaged.meta[MonopolyRules.PHASE] = MonopolyRules.Phase.MANAGE
	_own(mortgaged, 11, 0)
	mortgaged.meta[MonopolyRules.MORT][11] = 1
	_apply(mortgaged, Array(MonopolyRules.offer_path(
		1, 0, PackedInt32Array([11]), PackedInt32Array()
	)))
	_apply(mortgaged, [MonopolyRules.Act.ACCEPT])
	_equals(MonopolyRules.owner_of(mortgaged, 11), 1, "a casa hipotecada troca de dono")
	_equals(MonopolyRules.is_mortgaged(mortgaged, 11), true, "e continua hipotecada com o novo dono")

	# --- trocar para pagar o que se deve ---------------------------------------
	# É o momento em que a troca vale mais: vender uma cor a quem a quer rende mais
	# que hipotecá-la, e é a última saída de quem está quebrando.
	var owing := _fresh(2)
	_own(owing, 16, 0)
	_set_cash(owing, 0, 10)
	_set_cash(owing, 1, 900)
	owing.meta[MonopolyRules.PHASE] = MonopolyRules.Phase.RAISE
	owing.meta[MonopolyRules.DEBT] = 200
	owing.meta[MonopolyRules.CREDITOR] = 1
	var rescue := MonopolyRules.offer_path(
		1, -400, PackedInt32Array([16]), PackedInt32Array()
	)
	_equals(_rules.validate(owing, rescue) != null, true, "devendo, ainda dá para propor")
	_apply(owing, Array(rescue))
	_apply(owing, [MonopolyRules.Act.ACCEPT])
	_equals(MonopolyRules.phase_of(owing), MonopolyRules.Phase.MANAGE, "a troca quita a dívida")
	_equals(MonopolyRules.cash_of(owing, 0), 210, "e o que sobrou fica no bolso")

	_probe_trade_bot()
	_probe_trade_replay()


## O bot julga a proposta pelo que ela faz com o patrimônio **dele**, e a única
## distinção que ele faz é a que importa: fechar uma cor, ou perder uma fechada.
func _probe_trade_bot() -> void:
	var state := _fresh(2)
	state.meta[MonopolyRules.PHASE] = MonopolyRules.Phase.MANAGE
	_own(state, 1, 0)
	_own(state, 3, 1)

	# Trocar a rua de 60 por dinheiro de sobra: bom para quem responde.
	_apply(state, Array(MonopolyRules.offer_path(
		1, 200, PackedInt32Array(), PackedInt32Array([3])
	)))
	var choice := _rules.best_move(state, _rules.generate_moves(state))
	_equals(
		MonopolyRules.act_of(choice), MonopolyRules.Act.ACCEPT,
		"o bot aceita 200 por uma rua de 60"
	)
	_apply(state, [MonopolyRules.Act.REJECT])

	# A mesma rua por uma ninharia: recusada.
	_apply(state, Array(MonopolyRules.offer_path(
		1, 10, PackedInt32Array(), PackedInt32Array([3])
	)))
	choice = _rules.best_move(state, _rules.generate_moves(state))
	_equals(
		MonopolyRules.act_of(choice), MonopolyRules.Act.REJECT,
		"e recusa 10 pela mesma rua"
	)
	_apply(state, [MonopolyRules.Act.REJECT])

	# Agora a cor está fechada na mão de quem responde: o preço de tabela deixa de
	# valer, porque o que ele perde não é uma rua — é o grupo.
	_own(state, 1, 1)
	_own(state, 3, 1)
	_apply(state, Array(MonopolyRules.offer_path(
		1, 100, PackedInt32Array(), PackedInt32Array([1])
	)))
	choice = _rules.best_move(state, _rules.generate_moves(state))
	_equals(
		MonopolyRules.act_of(choice), MonopolyRules.Act.REJECT,
		"e não vende por 100 a rua que quebraria a cor fechada dele"
	)


## Uma partida com trocas se reconstrói do histórico. É o mesmo caminho da
## reconexão, e a troca é o único lance de tamanho variável — se `to_dict` ou o
## `validate` do outro lado lerem o caminho diferente, é aqui que aparece.
func _probe_trade_replay() -> void:
	var played := _fresh(3)
	played.meta[MonopolyRules.PHASE] = MonopolyRules.Phase.MANAGE
	_own(played, 1, 0)
	_own(played, 6, 1)
	_own(played, 8, 1)
	_apply(played, Array(MonopolyRules.offer_path(
		1, -50, PackedInt32Array([1]), PackedInt32Array([6, 8])
	)))
	_apply(played, [MonopolyRules.Act.ACCEPT])
	_apply(played, [MonopolyRules.Act.END])

	# A reconstrução parte da mesma posição armada, e só o histórico é repetido.
	var rebuilt := _fresh(3)
	rebuilt.meta[MonopolyRules.PHASE] = MonopolyRules.Phase.MANAGE
	_own(rebuilt, 1, 0)
	_own(rebuilt, 6, 1)
	_own(rebuilt, 8, 1)
	for data in played.history:
		var move := Move.from_dict(data)
		var checked := _rules.validate(rebuilt, move.path)
		if checked == null:
			_fail("o lance %s da troca não sobreviveu ao replay" % [move.path])
			return
		_rules.apply_move(rebuilt, checked)

	_equals(
		str(rebuilt.meta[MonopolyRules.OWNER]), str(played.meta[MonopolyRules.OWNER]),
		"o replay de uma troca devolve as mesmas escrituras"
	)
	_equals(
		str(rebuilt.meta[MonopolyRules.CASH]), str(played.meta[MonopolyRules.CASH]),
		"e os mesmos caixas"
	)


# --- cópia --------------------------------------------------------------------


## O teste que existe por causa de um comentário: `MatchState.clone()` copia
## `meta` de forma **rasa**. Sete vetores sobrevivem a isso só porque
## `PackedInt32Array` é cópia-na-escrita. Trocar um deles por `Array` não quebra
## nada visível — passa a corromper a partida quando o bot explorar variantes.
func _probe_clone() -> void:
	print("independência da cópia")
	var state := _fresh(4)
	_own(state, 1, 0)
	_set_cash(state, 0, 999)
	_place(state, 2, 17)

	var copy := state.clone()
	_apply(copy, [MonopolyRules.Act.BUILD, 1])
	_set_cash(copy, 1, 1)
	copy.meta[MonopolyRules.POS][2] = 33
	copy.meta[MonopolyRules.OWNER][5] = 3
	copy.meta[MonopolyRules.MORT][1] = 1
	copy.meta[MonopolyRules.OUT][3] = 1
	copy.meta[MonopolyRules.JAIL][1] = 0
	copy.meta[MonopolyRules.CARDS][0] = 2

	_equals(MonopolyRules.houses_on(state, 1), 0, "construir na cópia não constrói no original")
	_equals(MonopolyRules.cash_of(state, 0), 999, "nem mexe no caixa")
	_equals(MonopolyRules.cash_of(state, 1), BoardData.START_CASH, "de ninguém")
	_equals(MonopolyRules.position_of(state, 2), 17, "nem no peão")
	_equals(MonopolyRules.owner_of(state, 5), MonopolyRules.NO_OWNER, "nem na propriedade")
	_equals(MonopolyRules.is_mortgaged(state, 1), false, "nem na hipoteca")
	_equals(MonopolyRules.is_out(state, 3), false, "nem na eliminação")
	_equals(MonopolyRules.in_jail(state, 1), false, "nem na cadeia")
	_equals(MonopolyRules.jail_cards_of(state, 0), 0, "nem nas cartas")


# --- geometria do tabuleiro ---------------------------------------------------


## O anel de 40 retângulos fecha: os quatro lados encostam nos cantos, nenhuma
## casa sai do quadrado, e casas vizinhas se tocam sem sobrepor.
##
## Um erro de meia unidade aqui não trava nada — deixa uma fresta entre duas
## casas, ou uma casa sobrando por cima da vizinha, e ninguém repara olhando um
## print. Repara olhando o aparelho, semanas depois.
##
## Tudo é conferido nas **funções estáticas** de `MonopolyFace`, sem instanciar
## nó nenhum. É o que torna este teste possível sem tela: as mesmas funções
## respondem ao desenho do tampo, em pixels, e ao mundo 3D, em unidades — o que
## se confere aqui é a conta, e ela é a mesma nos dois.
func _probe_geometry() -> void:
	print("geometria do anel")
	# Escala arbitrária: a conta é proporcional, e um número redondo torna as
	# falhas legíveis.
	var unit := 40.0
	var board := Rect2(Vector2.ZERO, Vector2.ONE * unit * MonopolyFace.SPAN)

	var covered := 0.0
	for tile in BoardData.SIZE:
		var rect := MonopolyFace.tile_rect(tile, unit, Vector2.ZERO)
		covered += rect.size.x * rect.size.y
		if not board.grow(0.5).encloses(rect):
			_fail("a casa %d sai do tabuleiro: %s fora de %s" % [tile, rect, board])
		# Cada casa toca a borda do próprio lado — é o que a mantém no anel em vez
		# de flutuar no miolo.
		var edge_touch := (
			is_equal_approx(rect.position.x, board.position.x)
			or is_equal_approx(rect.position.y, board.position.y)
			or is_equal_approx(rect.end.x, board.end.x)
			or is_equal_approx(rect.end.y, board.end.y)
		)
		if not edge_touch:
			_fail("a casa %d não encosta em borda nenhuma" % tile)

	# Área do anel: o quadrado inteiro menos o miolo. Confere as duas larguras de
	# uma vez — se canto e casa comum não somassem o lado, a conta não fecharia.
	var side := unit * MonopolyFace.SPAN
	var hole := side - 2.0 * unit * MonopolyFace.CORNER
	_equals(
		is_equal_approx(covered, side * side - hole * hole), true,
		"as 40 casas cobrem o anel exatamente, sem fresta nem sobreposição"
	)

	# Casas consecutivas encostam. Um `for` do 0 ao 39 fechando no 0 de novo, que
	# é o que "anel" quer dizer.
	for tile in BoardData.SIZE:
		var here := MonopolyFace.tile_rect(tile, unit, Vector2.ZERO)
		var next := MonopolyFace.tile_rect((tile + 1) % BoardData.SIZE, unit, Vector2.ZERO)
		if not here.grow(unit * 0.02).intersects(next):
			_fail("a casa %d não encosta na %d" % [tile, (tile + 1) % BoardData.SIZE])

	# Os quatro cantos são quadrados, e são os únicos.
	for tile in BoardData.SIZE:
		var rect := MonopolyFace.tile_rect(tile, unit, Vector2.ZERO)
		var square := is_equal_approx(rect.size.x, rect.size.y)
		if MonopolyFace.is_corner(tile) != square:
			_fail("a casa %d tem o formato errado para a posição dela" % tile)

	# "Dentro" aponta mesmo para o miolo: somar o vetor ao centro da casa
	# aproxima do centro do tabuleiro.
	var middle := board.get_center()
	for tile in BoardData.SIZE:
		var center := MonopolyFace.tile_rect(tile, unit, Vector2.ZERO).get_center()
		var moved := center + MonopolyFace.inward(tile) * unit
		if moved.distance_to(middle) >= center.distance_to(middle):
			_fail("o 'dentro' da casa %d aponta para fora" % tile)

	_probe_world()


## A ponte entre o desenho e o mundo 3D.
##
## O tampo é o mesmo retângulo recentrado na origem, e o `y` do desenho vira o
## `z` do mundo. Se essas duas conversões discordarem, a casinha de plástico
## pousa ao lado da faixa de cor pintada em vez de em cima dela — e o erro é de
## meia casa, que parece proposital.
func _probe_world() -> void:
	var half := MonopolyFace.SPAN * 0.5
	for tile in BoardData.SIZE:
		var center := MonopolyBoard3D.tile_center(tile)
		if absf(center.x) > half + 0.001 or absf(center.z) > half + 0.001:
			_fail("a casa %d cai fora do tampo no mundo: %s" % [tile, center])
		if not is_equal_approx(center.y, MonopolyBoard3D.BOARD_THICKNESS):
			_fail("a casa %d não está na altura do tampo" % tile)
		# "Ao longo" é perpendicular a "para dentro", os dois deitados no tampo.
		var toward := MonopolyBoard3D.tile_inward(tile)
		var along := MonopolyBoard3D.tile_along(tile)
		if not is_zero_approx(toward.dot(along)):
			_fail("na casa %d o comprimento não é perpendicular à profundidade" % tile)
		if not is_zero_approx(toward.y) or not is_zero_approx(along.y):
			_fail("na casa %d os eixos saem do plano do tampo" % tile)

	# A construção pousa **sobre** a faixa de cor: o ponto na fração da faixa tem
	# de cair dentro da faixa que o tampo pintou.
	for tile in BoardData.SIZE:
		if not BoardData.can_build_on(tile):
			continue
		var spot := MonopolyBoard3D.tile_spot(tile, MonopolyFace.BAND_AT, 0.0)
		var center := MonopolyBoard3D.tile_center(tile)
		var into := (spot - center).dot(MonopolyBoard3D.tile_inward(tile))
		var band_middle := MonopolyFace.CORNER * 0.5 - MonopolyFace.BAND_DEPTH * 0.5
		if not is_equal_approx(into, band_middle):
			_fail("a construção da casa %d não pousa no meio da faixa de cor" % tile)

	# E o peão fica entre a faixa e o nome: mais para dentro que o nome, mais
	# para fora que a faixa. É o que impede o peão de tapar a única palavra da
	# casa e de sentar em cima das casinhas.
	_equals(
		MonopolyFace.BAND_AT < MonopolyFace.PAWN_AT
		and MonopolyFace.PAWN_AT < MonopolyFace.NAME_AT
		and MonopolyFace.NAME_AT < MonopolyFace.PRICE_AT,
		true,
		"faixa, peão, nome e preço se sucedem da borda de dentro para a de fora"
	)


# --- o caminho que o peão anda ------------------------------------------------


## A cena converte "estava em X, agora está em Y" no caminho a percorrer, e é ela
## que decide se a volta é pela frente ou de ré.
##
## O estado guarda só o **destino** — o peão já chegou quando a animação começa.
## Se o caminho errar, o peão anda pelo lado errado do tabuleiro e cruza a
## Partida na frente de quem acabou de não receber salário nenhum: a tela
## contando uma história que as regras negam.
func _probe_walk() -> void:
	print("caminho da caminhada")
	var short_hop: PackedInt32Array = BoardData.steps_between(5, 8)
	_equals(Array(short_hop), [6, 7, 8], "andar três casas passa pelas três")

	# A volta fecha: da casa 38, um sete cruza a Partida e continua na 5.
	var around: PackedInt32Array = BoardData.steps_between(38, 5, false)
	_equals(
		Array(around), [39, 0, 1, 2, 3, 4, 5],
		"a volta pela frente atravessa a Partida em vez de voltar por trás"
	)

	# De ré, e curto: é a carta "volte três casas", a única que anda para trás.
	var back: PackedInt32Array = BoardData.steps_between(36, 33, true)
	_equals(Array(back), [35, 34, 33], "de ré, casa a casa, sem dar a volta")

	# Ficar parado não é um caminho. Sem isto, um lance que não move o peão
	# dispararia uma animação de 40 casas — o laço só para quando reencontra a
	# origem.
	_equals(BoardData.steps_between(12, 12, false).size(), 0, "quem não sai do lugar não anda")

	# O destino é sempre alcançado, de qualquer casa para qualquer casa, pelos
	# dois sentidos: um laço que erra a condição de parada roda o tabuleiro
	# inteiro e devolve um caminho de 40.
	for from in BoardData.SIZE:
		for to in BoardData.SIZE:
			for backward in [false, true]:
				var path: PackedInt32Array = BoardData.steps_between(from, to, backward)
				if from == to:
					continue
				if path.is_empty() or path[path.size() - 1] != to:
					_fail("o caminho de %d a %d (ré=%s) não chega" % [from, to, backward])
				if path.size() >= BoardData.SIZE:
					_fail("o caminho de %d a %d (ré=%s) deu a volta inteira" % [from, to, backward])

	# Só a carta de recuar recua; qualquer outra carta e qualquer rolagem vão para
	# a frente, cruzando a Partida se for o caso.
	_equals(
		BoardData.card_walks_backward(
			BoardData.CHANCE, _card_index(BoardData.CHANCE, BoardData.Effect.MONEY)
		),
		false, "uma carta de dinheiro não anda de ré"
	)
	_equals(
		BoardData.card_walks_backward(
			BoardData.CHANCE, _card_index(BoardData.CHANCE, BoardData.Effect.MOVE_TO)
		),
		false, "nem uma de 'avance até', que atravessa o tabuleiro pela frente"
	)
	_equals(
		BoardData.card_walks_backward(
			BoardData.CHANCE, _card_index(BoardData.CHANCE, BoardData.Effect.MOVE_BY)
		),
		true, "e a de recuar três casas é a única que recua"
	)


# --- partida inteira ----------------------------------------------------------


## Joga partidas inteiras escolhendo lances ao acaso, com semente fixa.
##
## Não é teste de qualidade de jogo — é teste de **máquina de fases**. O que se
## verifica é que nenhuma sequência de fases chega a uma lista de lances vazia
## com a partida ainda em andamento, que é como um turno trava com quatro pessoas
## esperando; e que a partida realmente acaba.
func _probe_playout() -> void:
	print("partidas completas")
	for seed_value in [1, 7, 42, 1337, 90210]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var state := _fresh(4, 25)
		var plies := 0
		while _rules.winner(state) < 0 and plies < 20000:
			var moves := _rules.generate_moves(state)
			if moves.is_empty():
				_fail(
					"semente %d travou na fase %d, rodada %d"
					% [seed_value, MonopolyRules.phase_of(state), MonopolyRules.round_of(state)]
				)
				break
			_rules.apply_move(state, moves[rng.randi_range(0, moves.size() - 1)])
			plies += 1
			_check_invariants(state, seed_value)
		if _rules.winner(state) < 0:
			_fail("semente %d não terminou em %d lances" % [seed_value, plies])

	# E até a falência, sem limite de rodadas: alguém tem de sobrar sozinho.
	var rng_long := RandomNumberGenerator.new()
	rng_long.seed = 2024
	var long_game := _fresh(3, 0)
	var steps := 0
	while _rules.winner(long_game) < 0 and steps < 60000:
		var moves := _rules.generate_moves(long_game)
		if moves.is_empty():
			_fail("partida até a falência travou na fase %d" % MonopolyRules.phase_of(long_game))
			break
		_rules.apply_move(long_game, moves[rng_long.randi_range(0, moves.size() - 1)])
		steps += 1
	_equals(
		_rules.winner(long_game) >= 0, true,
		"a partida até a falência termina com um vencedor"
	)
	_equals(
		MonopolyRules.alive_players(long_game).size(), 1,
		"e sobra exatamente um"
	)


## Invariantes que não podem ser violadas em nenhum ponto da partida. Rodam a
## cada lance porque uma violação transitória — caixa negativo entre duas linhas
## de `apply_move` — é justamente o tipo de erro que só aparece uma vez em mil.
func _check_invariants(state: MatchState, seed_value: int) -> void:
	for player in MonopolyRules.seats_of(state):
		if MonopolyRules.cash_of(state, player) < 0:
			_fail("semente %d: caixa negativo no jogador %d" % [seed_value, player])
		var position := MonopolyRules.position_of(state, player)
		if position < 0 or position >= BoardData.SIZE:
			_fail("semente %d: peão fora do tabuleiro (%d)" % [seed_value, position])
		# Eliminado não pode ter ficado dono de nada.
		if MonopolyRules.is_out(state, player):
			if not MonopolyRules.deeds_of(state, player).is_empty():
				_fail("semente %d: jogador %d saiu com escrituras" % [seed_value, player])
	for tile in BoardData.SIZE:
		var built := MonopolyRules.houses_on(state, tile)
		if built < 0 or built > BoardData.HOTEL:
			_fail("semente %d: casa %d com %d construções" % [seed_value, tile, built])
		if built > 0 and MonopolyRules.is_mortgaged(state, tile):
			_fail("semente %d: casa %d hipotecada e construída" % [seed_value, tile])


## Partidas inteiras decididas pela heurística, e não ao acaso.
##
## O que se verifica não é qualidade de jogo — é que a heurística **sempre tem o
## que responder**. Um `null` numa fase qualquer trava a vez de um bot, e com
## quatro cadeiras de máquina isso trava a partida inteira; jogando, só apareceria
## depois de dezenas de turnos, com as pessoas esperando.
##
## Também prova que ela não empaca: um bot que respondesse "construir" para sempre
## nunca encerraria o turno, e a partida rodaria sem sair do lugar. O teto de
## lances pega isso.
func _probe_bot() -> void:
	print("partidas entre bots")
	for seed_value in [3, 17, 2718]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		seed(seed_value)
		var state := _fresh(4, 30)
		var plies := 0
		while _rules.winner(state) < 0 and plies < 20000:
			var moves := _rules.generate_moves(state)
			if moves.is_empty():
				_fail("semente %d: fase %d sem lance nenhum" % [
					seed_value, MonopolyRules.phase_of(state)
				])
				break
			var choice := _rules.best_move(state, moves)
			if choice == null:
				_fail("semente %d: a heurística não respondeu na fase %d" % [
					seed_value, MonopolyRules.phase_of(state)
				])
				break
			# O lance escolhido tem de ser um dos oferecidos. Um `Move` montado
			# à mão pela heurística passaria por `apply_move` sem passar pelas
			# regras, e corromperia o estado em silêncio.
			var legal := false
			for move in moves:
				if move.path == choice.path:
					legal = true
					break
			if not legal:
				_fail("semente %d: a heurística devolveu um lance ilegal %s" % [
					seed_value, choice.path
				])
				break
			_rules.apply_move(state, choice)
			plies += 1
			_check_invariants(state, seed_value)
		if _rules.winner(state) < 0:
			_fail("semente %d: a partida entre bots não terminou em %d lances" % [
				seed_value, plies
			])

	# E o bot compra: uma partida em que ninguém compra nada não exercita metade
	# das fases, e passaria em tudo acima sem provar nada.
	seed(99)
	var probe := _fresh(4, 12)
	while _rules.winner(probe) < 0:
		var choice := _rules.best_move(probe, _rules.generate_moves(probe))
		if choice == null:
			break
		_rules.apply_move(probe, choice)
	var owned := 0
	for tile in BoardData.SIZE:
		if MonopolyRules.owner_of(probe, tile) != MonopolyRules.NO_OWNER:
			owned += 1
	_equals(owned > 8, true, "depois de doze rodadas os bots compraram mais de oito casas")


## Repetir `history` devolve a mesma posição. É literalmente o que a reconexão
## faz, e é o motivo de os dois acasos — dado e carta — viajarem dentro do lance.
func _probe_replay() -> void:
	print("replay do histórico")
	var rng := RandomNumberGenerator.new()
	rng.seed = 314159
	var played := _fresh(4, 12)
	while _rules.winner(played) < 0:
		var moves := _rules.generate_moves(played)
		if moves.is_empty():
			break
		_rules.apply_move(played, moves[rng.randi_range(0, moves.size() - 1)])

	var rebuilt := _fresh(4, 12)
	for data in played.history:
		var move := Move.from_dict(data)
		var legal := false
		for candidate in _rules.generate_moves(rebuilt):
			if candidate.path == move.path:
				_rules.apply_move(rebuilt, candidate)
				legal = true
				break
		if not legal:
			_fail("o lance %s não é legal na reconstrução" % [move.path])
			return

	_equals(rebuilt.ply, played.ply, "a reconstrução tem o mesmo número de lances")
	for key in played.meta:
		var original = played.meta[key]
		var replayed = rebuilt.meta[key]
		if str(original) != str(replayed):
			_fail("'%s' diverge no replay: %s != %s" % [key, original, replayed])
	_equals(_rules.winner(rebuilt), _rules.winner(played), "e o mesmo vencedor")


# --- utilidades ---------------------------------------------------------------


func _fresh(players: int, limit := 0) -> MatchState:
	var rules := Rules.new()
	rules.seats = players
	rules.round_limit = limit
	return rules.initial_state()


## Aplica um lance montado à mão, sem passar pela geração. Usado para armar a
## posição; o que precisa ser legal é conferido por `_can`.
func _apply(state: MatchState, path: Array) -> void:
	var move := Move.new()
	move.path = PackedInt32Array(path)
	_rules.apply_move(state, move)


## O lance está na lista de legais desta posição.
func _can(state: MatchState, path: Array) -> bool:
	var wanted := PackedInt32Array(path)
	for move in _rules.generate_moves(state):
		if move.path == wanted:
			return true
	return false


func _place(state: MatchState, player: int, tile: int) -> void:
	state.meta[MonopolyRules.POS][player] = tile


func _own(state: MatchState, tile: int, player: int) -> void:
	state.meta[MonopolyRules.OWNER][tile] = player


func _set_cash(state: MatchState, player: int, amount: int) -> void:
	state.meta[MonopolyRules.CASH][player] = amount


func _jail(state: MatchState, player: int) -> void:
	state.meta[MonopolyRules.JAIL][player] = 0
	state.meta[MonopolyRules.POS][player] = BoardData.JAIL_TILE
	state.meta[MonopolyRules.PHASE] = MonopolyRules.Phase.JAILED


func _card_index(deck: int, effect: int) -> int:
	var cards := BoardData.deck(deck)
	for index in cards.size():
		if int(cards[index]["effect"]) == effect:
			return index
	return -1


func _equals(actual, expected, label: String) -> void:
	if actual == expected:
		print("  ok: %s" % label)
		return
	_fail("%s (esperado %s, veio %s)" % [label, expected, actual])


func _fail(message: String) -> void:
	_failures += 1
	printerr("  FALHOU: %s" % message)
