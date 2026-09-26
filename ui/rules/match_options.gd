class_name MatchOptions
extends RefCounted

## As opções da partida em curso, no formato que [TableRules] lê.
##
## Separado de `TableRules` de propósito: isto fala com `Game` e `Net`, e aquilo
## não pode — é o que deixa as regras da mesa serem testadas sem autoload. As
## opções já adotadas pela cena moram em `Game` (o formato da sinuca e o limite de
## Metrópole são copiados de `Net.option` quando a partida é em rede); o 0 e o 7
## do Uno, não, e por isso é lido da opção da sala.


static func current() -> Dictionary:
	var online := Game.mode == Game.Mode.ONLINE
	var options := {
		"players": Game.players_of(),
		"clock": Game.clock_label() if Game.has_clock() else "Sem relógio",
		"round_limit": Game.round_limit,
		"format": Game.pool_format,
		"sevens": Game.uno_sevens,
	}
	if online and Game.game_id == Game.UNO:
		options["sevens"] = Game.uno_sevens_of(Net.option)
	return options
