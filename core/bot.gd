class_name Bot
extends RefCounted

## Adversário local: minimax com poda alfa-beta sobre a mesma interface
## `Ruleset` que a tela usa. Não conhece xadrez nem damas — pede os lances,
## aplica, e pergunta quanto a posição vale. Um terceiro jogo entra escrevendo
## `evaluate()` na sua regra, e mais nada aqui.
##
## Roda numa `Thread`. Não é otimização prematura: o celular leva de meio a dois
## segundos numa posição de meio-jogo, e na thread principal isso seria a tela
## congelada — o relógio parado, o toque ignorado, e a impressão de um jogo que
## travou. Na thread, a partida continua respondendo enquanto ele pensa.
##
## O estado é **clonado** antes de sair da thread principal, e a regra é
## instanciada aqui dentro. Nada que a busca toca é visível para a cena, então
## não há o que sincronizar além do fim do trabalho.

## Ninguém fora daqui espera pela thread: a cena consulta a cada quadro e segue a
## vida. `wait_to_finish` só é chamado quando o trabalho já terminou — ou quando
## a partida está sendo abandonada, e aí esperar é o certo.

const MATE := 1_000_000.0

## Níveis oferecidos ao jogador.
##
## O limite é **tempo**, não número de nós ou profundidade fixa, e essa é a
## escolha que faz o bot funcionar fora desta máquina. Uma profundidade que sai
## em meio segundo no desktop leva dez no celular antigo; um teto de milissegundos
## se traduz sozinho — o aparelho lento procura menos fundo e responde na mesma
## hora. `depth` fica como teto de sanidade, para um final quase vazio não gastar
## o tempo todo confirmando o óbvio.
##
## `slip` é a chance de o bot **não** jogar o melhor lance que encontrou, e é o
## que faz a diferença entre os níveis ser sentida. Só reduzir a profundidade não
## produz um adversário fraco: mesmo procurando dois lances à frente ele nunca
## deixa uma peça de graça, e para quem está aprendendo isso já é um muro. O
## deslize dá o erro humano que a busca não comete sozinha — e é um lance da
## lista ordenada, não um lance aleatório, então nunca vira palhaçada.
const LEVELS := [
	{"label": "Fácil", "depth": 2, "ms": 250, "slip": 0.5, "spread": 4},
	{"label": "Médio", "depth": 4, "ms": 900, "slip": 0.15, "spread": 2},
	{"label": "Difícil", "depth": 6, "ms": 2500, "slip": 0.0, "spread": 0},
]

## Nós entre duas consultas ao relógio. Perguntar as horas a cada nó custaria uma
## fatia do que se está tentando economizar.
const CLOCK_EVERY := 255

## Até onde a busca de sossego desce atrás de capturas.
##
## Ela não tinha teto. Uma cadeia de capturas termina sozinha, então a recursão
## sempre acabava — só que "sozinha" pode ser oito lances abaixo, com a árvore de
## recapturas inteira no caminho, e era ali que ia quase todo o orçamento de
## tempo: a raiz a uma profundidade custava 1131 ms, dos quais 6 ms eram a raiz.
##
## **Seis, e não quatro**, e o número foi medido e não escolhido. Com quatro, a
## ordenação da raiz muda — `d4` sai da frente na profundidade 2 —, então o teto
## estaria cortando trocas que importam. Com seis, as notas saem **idênticas** às
## da versão sem teto nas profundidades 2 e 3, e a 3 cai de 101 s para 8,4 s.
## Cortar mais barato existe; cortar de graça é este.
const QUIET_DEPTH := 6

## Folga da poda por diferença, na escala de `evaluate` — dois peões.
##
## A poda descarta a captura que não alcança `alpha` nem no melhor caso, e o
## "melhor caso" é medido só em material. A margem paga o que o material não vê:
## a casa que a peça passa a ocupar, a coluna que abre. Larga demais não poda
## nada; estreita demais poda a captura que valia pela posição e não pelo peão.
const DELTA_MARGIN := 200.0

var _thread: Thread = null
var _ruleset: Ruleset = null
var _found: Move = null
var _deadline := 0
var _ticks := 0
var _expired := false
var _abandoned := false


static func level_label(index: int) -> String:
	return str(LEVELS[clampi(index, 0, LEVELS.size() - 1)]["label"])


## Começa a pensar. Retorna na hora; o lance sai por `take_move()`.
##
## `budget_ms` é um teto que vem de fora e só encurta, nunca alonga. Existe para
## o relógio: o bot não sabe que existe um, e sem esse limite o nível Difícil
## gastaria os mesmos dois segundos e meio por lance com dez minutos na conta ou
## com cinco segundos — e perderia no tempo pensando bonito.
func think(game_id: StringName, state: MatchState, level: int, budget_ms := 0) -> void:
	var settings: Dictionary = LEVELS[clampi(level, 0, LEVELS.size() - 1)]
	if budget_ms > 0 and budget_ms < int(settings["ms"]):
		settings = settings.duplicate()
		settings["ms"] = budget_ms
	var position := state.clone()
	_found = null
	_abandoned = false

	# Onde a thread não sobe (exportações de uma linha só de execução), a busca
	# roda aqui mesmo. Fica lenta e visível, mas jogável — melhor que um bot que
	# nunca responde. Tentar e olhar o erro é mais honesto que perguntar à
	# plataforma: a resposta que importa é se *esta* thread começou.
	_thread = Thread.new()
	if _thread.start(_decide.bind(game_id, position, settings)) != OK:
		_thread = null
		_found = _decide(game_id, position, settings)


func thinking() -> bool:
	return _thread != null and _thread.is_alive()


## O lance, quando houver. `null` significa "ainda pensando" — não "sem lance":
## uma posição sem lance legal nunca chega aqui, porque a partida já acabou.
func take_move() -> Move:
	if _thread == null:
		var immediate := _found
		_found = null
		return immediate
	if _thread.is_alive():
		return null
	var move: Move = _thread.wait_to_finish()
	_thread = null
	return move


## Encerra o trabalho antes de sair da partida. A thread não é interrompível de
## fora, então o que se faz é pedir que ela desista no próximo nó e esperar —
## sair da cena com uma thread viva derruba o processo, e é uma queda que só
## aparece em quem fecha a partida no segundo errado.
func abandon() -> void:
	_abandoned = true
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_found = null


# --- busca -------------------------------------------------------------------


## Aprofundamento iterativo: procura a 1 lance, depois a 2, depois a 3, e guarda
## o melhor de cada rodada completa. Parece desperdício refazer o trabalho, e não
## é — a rodada rasa custa uma fração da funda e **ordena os lances** para ela,
## que é o que faz a poda alfa-beta cortar cedo.
##
## Também é o que torna o orçamento de nós utilizável: estourar no meio de uma
## rodada não deixa o bot sem resposta, deixa com a resposta da rodada anterior.
func _decide(game_id: StringName, state: MatchState, settings: Dictionary) -> Move:
	_ruleset = _make_ruleset(game_id)
	_deadline = Time.get_ticks_msec() + int(settings["ms"])
	_ticks = 0
	_expired = false

	var moves := _ruleset.generate_moves(state)
	if moves.is_empty():
		return null
	if moves.size() == 1:
		return moves[0]

	# A ordem da **primeira** rodada sai de uma avaliação imediata, e não do
	# gerador.
	#
	# É a segunda metade da correção do passeio da torre. Garantir que o lance
	# devolvido foi pontuado não bastou: numa posição de meio-jogo cheia, a rodada
	# de profundidade 1 leva quase oito segundos, nenhum nível a termina, e o que
	# sobra pontuado são os primeiros lances da lista. O gerador varre o tabuleiro
	# de a1 para h8, então esses primeiros são sempre os da mesma peça — a da casa
	# mais baixa, que depois do roque é a torre. O bot passou de "joga a torre sem
	# olhar" para "joga a torre depois de olhar", que é o mesmo lance.
	#
	# Ordenados por avaliação imediata, os poucos que couberem no orçamento são os
	# mais promissores em vez dos mais à esquerda. Custa uma varredura sem
	# recursão — uns dois milissegundos numa posição cheia.
	var ranked := _static_order(state, moves)
	var best: Move = null
	for depth in range(1, int(settings["depth"]) + 1):
		var round := _rank(state, ranked, depth)
		var order: Array = round["order"]
		if bool(round["complete"]):
			# Só uma rodada inteira substitui a anterior. Uma rodada cortada no meio
			# viu alguns lances a mais fundo que outros, e comparar os dois seria
			# comparar medidas diferentes.
			ranked = order
			best = _pick(ranked, settings)
		elif best == null and not order.is_empty():
			# Nenhuma rodada inteira coube no orçamento. O melhor entre os poucos que
			# deu tempo de olhar é uma resposta fraca — e é uma resposta. Antes daqui
			# a busca desistia e devolvia `moves[0]`, que é o primeiro lance que o
			# gerador produz e não foi olhado por ninguém.
			best = order[0]
		if _stop():
			break
	# Nem um lance pontuado: orçamento tão curto que a primeira busca já estourou.
	# O primeiro da ordem estática é fraco, mas é uma opinião.
	return best if best != null else ranked[0]


## Verdadeiro quando o tempo acabou ou a partida foi abandonada. Uma vez
## verdadeiro, continua verdadeiro: a busca desmonta sozinha em vez de ficar
## conferindo o relógio no caminho de volta.
func _stop() -> bool:
	if _expired or _abandoned:
		return true
	_ticks += 1
	if (_ticks & CLOCK_EVERY) == 0:
		_expired = Time.get_ticks_msec() >= _deadline
	return _expired


## Pontua cada lance da raiz e devolve `{"order": [...], "complete": bool}`, do
## melhor para o pior. A ordem alimenta a próxima profundidade; a pontuação
## escolhe o lance.
##
## Uma rodada cortada no meio **também devolve o que viu**, e é essa a diferença
## que conserta o bot que andava em círculo. Antes ela devolvia uma lista vazia, e
## quem chamava não tinha como distinguir "não deu tempo de olhar nada" de "não
## deu tempo de terminar" — nos dois casos ele caía no primeiro lance do gerador,
## que ninguém pontuou. Com o gerador varrendo o tabuleiro de a1 para h8, esse
## lance é o da peça na casa mais baixa: depois do roque, a torre. Daí o passeio
## `Tf1 Te1 Tf1 Te1` até alguma captura mudar a lista.
##
## `complete` é falso quando qualquer lance ficou de fora, e só uma rodada
## completa vale como ordenação para a profundidade seguinte.
func _rank(state: MatchState, moves: Array, depth: int) -> Dictionary:
	var scored := []
	for move in moves:
		var next := state.clone()
		_ruleset.apply_move(next, move)
		var score := -_search(next, depth - 1, -MATE * 2.0, MATE * 2.0)
		if _stop():
			# A pontuação **deste** não vale: a busca que a produziu foi cortada no
			# meio. Os anteriores foram medidos inteiros e ficam.
			break
		scored.append({"move": move, "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	var ordered := []
	for entry in scored:
		ordered.append(entry["move"])
	return {"order": ordered, "complete": ordered.size() == moves.size()}


## Os lances da raiz ordenados por avaliação imediata, **sem relógio**.
##
## Sem recursão e sem busca de sossego — clonar, aplicar e medir, uma vez por
## lance. Custa milissegundos em qualquer posição e em qualquer aparelho, e por
## isso ignora o orçamento: é a diferença entre uma rodada cortada que viu os
## lances promissores e uma que viu os lances da peça mais à esquerda.
##
## Serve a dois propósitos de uma vez, e o segundo é de graça: além de tirar o
## viés da ordem de geração, ela é uma ordenação melhor para a poda alfa-beta da
## primeira rodada do que a ordem do tabuleiro.
func _static_order(state: MatchState, moves: Array) -> Array:
	var scored := []
	for move in moves:
		var next := state.clone()
		_ruleset.apply_move(next, move)
		scored.append({"move": move, "score": -_score(next)})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	var ordered := []
	for entry in scored:
		ordered.append(entry["move"])
	return ordered


## O melhor lance — ou, com a chance do nível, um dos logo abaixo dele.
func _pick(ordered: Array, settings: Dictionary) -> Move:
	var spread := mini(int(settings["spread"]), ordered.size() - 1)
	if spread <= 0 or randf() >= float(settings["slip"]):
		return ordered[0]
	return ordered[1 + randi() % spread]


## Negamax: cada lado maximiza a própria pontuação, e a do adversário é a mesma
## com o sinal trocado. `evaluate` fala sempre em nome das brancas, então a
## conversão acontece num lugar só (`_score`) em vez de espalhada pela recursão —
## que é onde esse sinal costuma se perder.
func _search(state: MatchState, depth: int, alpha: float, beta: float) -> float:
	if depth <= 0:
		return _quiescence(state, alpha, beta)
	if _stop():
		return _score(state)

	var moves := _ruleset.generate_moves(state)
	if moves.is_empty():
		return _terminal(state)

	for move in _ordered(moves):
		var next := state.clone()
		_ruleset.apply_move(next, move)
		var score := -_search(next, depth - 1, -beta, -alpha)
		if score >= beta:
			return beta
		if score > alpha:
			alpha = score
		if _stop():
			break
	return alpha


## Busca de sossego: no fundo da árvore, continua enquanto houver capturas.
##
## Sem isto o bot mede a posição no meio de uma troca. Ele come o peão defendido
## no último lance da busca, marca o ponto e nunca vê a recaptura — que é o
## sintoma clássico e o que faz um bot com boa avaliação parecer aleatório.
##
## `stand_pat` é a opção de não capturar nada: só vale a pena continuar se a
## captura melhorar o que já se tem parado.
func _quiescence(state: MatchState, alpha: float, beta: float, left := QUIET_DEPTH) -> float:
	var stand_pat := _score(state)
	if stand_pat >= beta:
		return beta
	if stand_pat > alpha:
		alpha = stand_pat
	if left <= 0 or _stop():
		return alpha

	for entry in _captures(state):
		var move: Move = entry["move"]
		# Poda por diferença: mesmo embolsando a peça de graça e sem recaptura
		# nenhuma, esta captura não alcança o que já se tem parado. A margem cobre
		# o que a posição pode render além do material.
		#
		# Como a lista vem da maior para a menor, a primeira que não passa condena
		# todas as seguintes — elas ganham menos ainda.
		if stand_pat + float(entry["gain"]) + DELTA_MARGIN <= alpha:
			break
		var next := state.clone()
		_ruleset.apply_move(next, move)
		var score := -_quiescence(next, -beta, -alpha, left - 1)
		if score >= beta:
			return beta
		if score > alpha:
			alpha = score
		if _stop():
			break
	return alpha


## As capturas da posição, da que ganha mais material para a que ganha menos.
##
## A ordem é o que faz a poda alfa-beta e a poda por diferença funcionarem: comer
## a dama primeiro levanta o `alpha` de uma vez, e a partir daí quase toda captura
## menor é descartada sem ser buscada. Na ordem do tabuleiro, o mesmo corte só
## acontecia depois de descer a árvore inteira das capturas ruins.
##
## O ganho vem junto na lista porque ele é calculado aqui e usado logo em seguida
## pela poda — pedi-lo duas vezes seria pagar duas vezes.
func _captures(state: MatchState) -> Array:
	var found := []
	for move in _ruleset.generate_moves(state):
		if not move.is_capture():
			continue
		found.append({"move": move, "gain": _ruleset.capture_gain(state, move)})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["gain"] > b["gain"])
	return found


## Capturas primeiro, e as maiores antes. A poda alfa-beta só corta quando o bom
## lance aparece cedo; com a ordem errada ela examina a árvore inteira e vira
## minimax puro, com o mesmo resultado pelo dobro do preço.
##
## Uma passada, e sem `sort_custom`: a comparação por lambda é chamada n log n
## vezes por nó, e uma lambda em GDScript custa uma chamada de função inteira.
## Dividir em duas listas dá a ordem que interessa — o que ganha material antes
## do resto — pelo custo de percorrer a lista uma vez.
func _ordered(moves: Array[Move]) -> Array[Move]:
	var loud: Array[Move] = []
	var quiet: Array[Move] = []
	for move in moves:
		if move.is_capture() or move.promotion != Board.Kind.EMPTY:
			loud.append(move)
		else:
			quiet.append(move)
	if loud.is_empty():
		return moves
	loud.append_array(quiet)
	return loud


## Fim de partida visto de dentro da busca. O `- state.ply` faz o mate próximo
## valer mais que o distante: sem ele o bot enxerga mate em 1 e mate em 5 como a
## mesma coisa, escolhe qualquer um, e fica empurrando peça com a vitória na mão.
func _terminal(state: MatchState) -> float:
	var result := _ruleset.outcome(state)
	if result == Ruleset.Outcome.DRAW or result == Ruleset.Outcome.ONGOING:
		return 0.0
	var winner := Board.Side.WHITE if result == Ruleset.Outcome.WHITE_WINS else Board.Side.BLACK
	var value := MATE - state.ply
	return value if winner == state.side_to_move else -value


func _score(state: MatchState) -> float:
	var white := _ruleset.evaluate(state)
	return white if state.side_to_move == Board.Side.WHITE else -white


## Instância própria, criada dentro da thread. As regras não guardam estado entre
## chamadas, então compartilhar a da cena funcionaria — e passaria a depender
## disso continuar verdade, que é o tipo de acoplamento que não se vê quebrar.
func _make_ruleset(game_id: StringName) -> Ruleset:
	if game_id == &"checkers":
		return CheckersRules.new()
	return ChessRules.new()
