class_name TrainingPanel
extends Control

## O treino: os erros das partidas revisadas, de volta como desafio no dia em
## que vencem (`Training`). Um cartão por vez; resolveu de primeira, ele volta
## mais tarde, senão volta amanhã.
##
## Por cima da tela "Você", como o histórico: fechar devolve a tela como estava.
##
## "Analisar partidas novas" é a porta para as partidas que nunca foram
## revisadas. Uma partida por vez numa thread, e o resultado é gravado na thread
## principal — é ela que grava o baralho a cada desafio, e duas escritas no
## mesmo `ConfigFile` de duas threads não combinam.

signal closed

var _challenge := ChallengeView.new()
var _context := Label.new()
var _empty := MessageCard.new()
var _analyse: Button = null

## Os vencidos desta sessão, na ordem em que vão sair.
var _queue: Array = []

var _review: GameReview = null
var _thread: Thread = null
var _todo: Array = []
var _done_count := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = AppTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)

	var safe := SafeAreaMargin.new()
	for side in ["left", "top", "right", "bottom"]:
		safe.add_theme_constant_override("margin_" + side, 16)
	safe.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	safe.add_child(column)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Treino"
	title.theme_type_variation = &"Title"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "Fechar"
	close_button.theme_type_variation = &"GhostButton"
	close_button.custom_minimum_size = Vector2(0, 44)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	column.add_child(header)

	_context.theme_type_variation = &"Hint"
	_context.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_context)

	_challenge.size_flags_vertical = SIZE_EXPAND_FILL
	_challenge.continue_label = "Próximo"
	_challenge.done.connect(_graded)
	column.add_child(_challenge)

	column.add_child(_empty)

	_analyse = Button.new()
	_analyse.theme_type_variation = &"GhostButton"
	_analyse.custom_minimum_size = Vector2(0, 52)
	_analyse.pressed.connect(_start_analysis)
	column.add_child(_analyse)

	_queue = Training.due(Prefs.training(), _now())
	_next()
	_refresh_analyse()


## Fecha o treino. É o que o voltar do sistema chama.
func close() -> void:
	_stop()
	closed.emit()
	queue_free()


func _exit_tree() -> void:
	_stop()


func _process(_delta: float) -> void:
	if _thread == null:
		return
	if _thread.is_alive():
		_analyse.text = "Analisando partida %d de %d… %d/%d lances" % [
			_done_count + 1, _done_count + _todo.size(), _review.progress, _review.total
		]
		return
	var entries: Array = _thread.wait_to_finish()
	_thread = null
	var game: Dictionary = _todo.pop_front()
	_done_count += 1
	Training.collect(game, entries)
	# Sem motor a análise volta vazia, e as próximas voltariam iguais.
	if entries.is_empty():
		_todo.clear()
		_refresh_analyse()
		_analyse.text = "Não foi possível analisar agora. Tentar de novo"
		return
	if not _todo.is_empty():
		_analyse_next()
		return
	# Os cartões novos entram na fila sem tirar da tela o desafio em jogo.
	var playing: Dictionary = _queue[0] if _challenge.visible else {}
	_queue = Training.due(Prefs.training(), _now())
	if playing.is_empty():
		_next()
	else:
		_queue = _queue.filter(func(card): return Training.key(card) != Training.key(playing))
		_queue.push_front(playing)
	_refresh_analyse()


func _next() -> void:
	while not _queue.is_empty():
		var card: Dictionary = _queue[0]
		var state := Training.position(card)
		if state != null:
			_context.text = _origin(card)
			_context.visible = true
			_empty.visible = false
			_challenge.visible = true
			_challenge.start(state, str(card["best"]), str(card["best_san"]), float(card["score"]), card["mate"])
			return
		# Cartão que não se refaz não tem como ser jogado: sai do baralho.
		_forget(card)
		_queue.pop_front()
	_challenge.visible = false
	_context.visible = false
	_empty.visible = true
	var deck := Prefs.training()
	if deck.is_empty():
		_empty.status.text = "Nenhum erro para treinar."
		_empty.detail.text = "Os erros das partidas de xadrez que você revisar viram desafio aqui."
		return
	_empty.status.text = "Nada para hoje."
	var soonest: int = deck.map(func(card): return int(card["due"])).min()
	var days := ceili(float(soonest - _now()) / Training.DAY)
	_empty.detail.text = "O próximo desafio volta %s." % ("amanhã" if days <= 1 else "em %d dias" % days)


func _graded(_solved: bool, clean: bool) -> void:
	var card: Dictionary = _queue.pop_front()
	var graded := Training.grade(card, clean, _now())
	var deck := Prefs.training()
	for i in deck.size():
		if Training.key(deck[i]) == Training.key(card):
			deck[i] = graded
	Prefs.set_training(deck)
	_next()


func _forget(card: Dictionary) -> void:
	Prefs.set_training(Prefs.training().filter(func(other): return Training.key(other) != Training.key(card)))


## "Da partida de 14/10 às 17:32 · Contra o bot (Avançado)". A partida pode já
## ter saído do histórico (ele guarda as 50 últimas); o cartão continua valendo.
func _origin(card: Dictionary) -> String:
	for game in Prefs.history():
		if int(game.get("at", -1)) == int(card["at"]):
			return "Da partida de %s · %s" % [HistoryPanel.when(int(card["at"])), game.get("against", "")]
	return "Da partida de %s" % HistoryPanel.when(int(card["at"]))


func _refresh_analyse() -> void:
	var count := Training.pending(Prefs.history()).size()
	_analyse.visible = count > 0 and _thread == null
	_analyse.disabled = false
	_analyse.text = "Analisar %d partida%s nova%s" % [count, "" if count == 1 else "s", "" if count == 1 else "s"]


func _start_analysis() -> void:
	_todo = Training.pending(Prefs.history())
	_done_count = 0
	if _todo.is_empty():
		return
	_analyse.disabled = true
	_analyse.visible = true
	_analyse_next()


func _analyse_next() -> void:
	_review = GameReview.new()
	_thread = Thread.new()
	_thread.start(_review.analyse.bind(_todo[0].get("moves", [])))


func _stop() -> void:
	if _thread != null:
		_review.abandon()
		_thread.wait_to_finish()
		_thread = null
	_todo.clear()


static func _now() -> int:
	return int(Time.get_unix_time_from_system())
