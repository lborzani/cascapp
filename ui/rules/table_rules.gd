class_name TableRules
extends RefCounted

## As regras **desta mesa**: o que vale nesta partida, com o estado de cada uma.
##
## Não mora no `.tres` de regras porque depende das opções da partida — o 0 e o 7
## do Uno ligado ou não, o formato da sinuca, o limite de rodadas de Metrópole. A
## página de regras responde "como se joga"; isto responde "o que vale aqui".
##
## Função pura: recebe as opções prontas em vez de ler `Game` e `Net`. É o que a
## deixa ser testada sem autoload — quem sabe as opções da partida em curso é
## [MatchOptions]. Os números saem das constantes das regras, para o texto não
## desatualizar quando uma regra mudar.
##
## Cada linha é `{label, state}`: o que a regra é, e como ela está nesta mesa.


static func for_game(id: StringName, options: Dictionary) -> Array[Dictionary]:
	match id:
		&"chess":
			return _chess(options)
		&"checkers":
			return _checkers(options)
		&"battleship":
			return _battleship()
		&"ludo":
			return _ludo()
		&"monopoly":
			return _monopoly(options)
		&"uno":
			return _uno(options)
		&"pool":
			return _pool(options)
		&"bomberman":
			return _bomberman()
	return []


static func _row(label: String, state: String) -> Dictionary:
	return {"label": label, "state": state}


static func _chess(options: Dictionary) -> Array[Dictionary]:
	return [
		_row("Ritmo", str(options.get("clock", "Sem relógio"))),
		_row("Roque, en passant e promoção", "sempre"),
		_row("Empate sem captura nem peão", "50 lances"),
		_row("Planejar lances na vez do outro", "em rede"),
	]


static func _checkers(options: Dictionary) -> Array[Dictionary]:
	return [
		_row("Ritmo", str(options.get("clock", "Sem relógio"))),
		_row("Capturar", "opcional"),
		_row("Dama", "voa"),
		_row("Empate só com damas", "%d lances" % CheckersRules.IDLE_DRAW_LIMIT),
	]


static func _battleship() -> Array[Dictionary]:
	return [
		_row("Frota", "%d navios, %d casas" % [BattleshipRules.SHIPS.size(), BattleshipRules.FLEET_CELLS]),
		_row("Navios encostados", "podem"),
		_row("Acertou", "a vez passa"),
	]


static func _ludo() -> Array[Dictionary]:
	return [
		_row("Sair da base", "só com %d" % LudoRules.EXIT_ROLL),
		_row("Tirou %d" % LudoRules.EXIT_ROLL, "joga de novo"),
		_row("Chegar", "número exato"),
		_row("Casas seguras", "saídas e estrelas"),
	]


static func _monopoly(options: Dictionary) -> Array[Dictionary]:
	var limit := int(options.get("round_limit", 0))
	return [
		_row("Fim", "até a falência" if limit <= 0 else "%d rodadas, maior patrimônio" % limit),
		_row("Salário da Partida", "M %d" % MonopolyBoard.GO_SALARY),
		_row("Fiança", "M %d" % MonopolyBoard.BAIL),
		_row("Leilão", "não há"),
	]


static func _uno(options: Dictionary) -> Array[Dictionary]:
	return [
		_row("0 e 7", "ligada" if bool(options.get("sevens", false)) else "desligada"),
		_row("Empilhar +2 e +4", "sempre"),
		_row("Duvidar do +4 e errar", "+%d cartas" % UnoRules.CHALLENGE_PENALTY),
		_row("Esquecer o UNO", "+%d cartas" % UnoRules.CATCH_PENALTY),
	]


static func _pool(options: Dictionary) -> Array[Dictionary]:
	if int(options.get("format", PoolRules.Format.KNOCKOUT)) == PoolRules.Format.BRAZILIAN:
		return [
			_row("Formato", "brasileira"),
			_row("Primeiro toque", "na bola da vez"),
			_row("Falta", "%d pontos ao adversário" % PoolRules.FOUL_POINTS),
			_row("Depois da falta", "branca na mão"),
		]
	return [
		_row("Formato", "mata-mata"),
		_row("Primeiro toque", "numa bola do adversário"),
		_row("Falta", "passa a vez"),
		_row("Bola sua na caçapa", "sai do jogo"),
	]


static func _bomberman() -> Array[Dictionary]:
	return [
		_row("Pavio", "%d segundos" % (BomberRules.FUSE / BomberRules.TICK_HZ)),
		_row("Fogo em quem pôs a bomba", "atinge"),
		_row("Prêmios", "bomba, fogo e velocidade"),
	]
