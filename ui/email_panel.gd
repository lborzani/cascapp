class_name EmailPanel
extends Control

## A conta e o e-mail: proteger a conta deste celular, ou voltar para uma conta
## protegida. Nos dois casos, primeiro o e-mail, depois o código que chegou nele.
##
## Por cima da tela "Você" ou da boas-vindas: fechar devolve a tela como estava.
## O e-mail não vira login. Ele só traz a conta de volta a um celular formatado
## ou novo, e por isso não há senha: quem prova que é dono do e-mail é o código.

signal closed
## Este celular voltou para a conta antiga. Sai antes de `closed`.
signal recovered

## Voltar para uma conta protegida, em vez de proteger esta. Escrito antes do
## `add_child`; o link "Já tenho uma conta protegida" também liga.
var recover := false

var _title: Label = null
var _intro: Label = null
var _email: LineEdit = null
var _send: Button = null
var _switch: Button = null
var _code: CodeInput = null
var _note: Label = null
var _resend: Button = null
var _email_step: Control = null
var _code_step: Control = null
## O e-mail para onde o último código foi.
var _sent_to := ""
var _busy := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = AppTheme.BACKGROUND
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	# Pára o toque: a tela de trás está viva.
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)

	var safe := SafeAreaMargin.new()
	for side in ["left", "top", "right", "bottom"]:
		safe.add_theme_constant_override("margin_" + side, 16)
	safe.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	safe.add_child(column)

	var header := HBoxContainer.new()
	_title = Label.new()
	_title.theme_type_variation = &"Title"
	_title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(_title)
	var close_button := Button.new()
	close_button.text = "Fechar"
	close_button.theme_type_variation = &"GhostButton"
	close_button.custom_minimum_size = Vector2(0, 44)
	close_button.pressed.connect(close)
	header.add_child(close_button)
	column.add_child(header)

	_intro = Label.new()
	_intro.theme_type_variation = &"Subtitle"
	_intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_intro)

	_email_step = VBoxContainer.new()
	_email_step.add_theme_constant_override("separation", 12)
	column.add_child(_email_step)
	_email = LineEdit.new()
	_email.placeholder_text = "seu@email.com"
	_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	_email.custom_minimum_size.y = 52
	_email.text_submitted.connect(func(_text: String) -> void: _send_code())
	_email_step.add_child(_email)
	_send = Button.new()
	_send.text = "Mandar código"
	_send.theme_type_variation = &"PrimaryButton"
	_send.custom_minimum_size.y = 52
	_send.pressed.connect(_send_code)
	_email_step.add_child(_send)
	# Quem formatou o celular cai numa conta nova, e o caminho até a antiga
	# começa aqui mesmo: é a linha "Proteja sua conta" que essa pessoa vê.
	_switch = Button.new()
	_switch.text = "Já tenho uma conta protegida"
	_switch.theme_type_variation = &"GhostButton"
	_switch.pressed.connect(func() -> void:
		Sound.play(Sound.Cue.TAP)
		recover = true
		_back_to_email()
	)
	_email_step.add_child(_switch)

	_code_step = VBoxContainer.new()
	_code_step.add_theme_constant_override("separation", 12)
	_code_step.visible = false
	column.add_child(_code_step)
	_code = CodeInput.new()
	_code.numeric()
	_code.completed.connect(_confirm)
	_code_step.add_child(_code)
	var again := HBoxContainer.new()
	_resend = Button.new()
	_resend.text = "Mandar de novo"
	_resend.theme_type_variation = &"GhostButton"
	_resend.pressed.connect(_send_code)
	again.add_child(_resend)
	var change := Button.new()
	change.text = "Trocar e-mail"
	change.theme_type_variation = &"GhostButton"
	change.pressed.connect(_back_to_email)
	again.add_child(change)
	_code_step.add_child(again)

	_note = Label.new()
	_note.theme_type_variation = &"Hint"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_note)

	_back_to_email()


## O que o voltar do sistema chama.
func close() -> void:
	closed.emit()
	queue_free()


func _back_to_email() -> void:
	_title.text = "Recuperar conta" if recover else "Proteger conta"
	if recover:
		_intro.text = "Digite o e-mail que protege a sua conta. Este celular passa a usar aquela conta, e o que ele tem agora (moedas e itens) fica para trás."
	else:
		_intro.text = "Se você formatar ou trocar de celular, volta para esta conta, com moedas, itens, amigos e Elo, pelo e-mail. Sem senha: a gente manda um código."
	_switch.visible = not recover
	_note.text = ""
	_email_step.visible = true
	_code_step.visible = false
	_focus(_email)


func _send_code() -> void:
	if _busy:
		return
	var email := _email.text.strip_edges().to_lower()
	if not _looks_like_email(email):
		_note.text = "Confira o e-mail."
		return
	Sound.play(Sound.Cue.TAP)
	_busy = true
	_send.disabled = true
	_resend.disabled = true
	_note.text = "Mandando…"
	var code := await Account.email_start(email, "recover" if recover else "protect")
	_busy = false
	_send.disabled = false
	_resend.disabled = false
	if not is_inside_tree():
		return
	match code:
		200:
			_sent_to = email
			# Para recuperar, o servidor responde igual quando o e-mail não
			# protege conta nenhuma; a frase não promete o que não sabe.
			if recover:
				_intro.text = "Se %s protege uma conta, o código chegou lá. Ele vale por 10 minutos." % Account.masked_email(email)
			else:
				_intro.text = "Mandamos um código para %s. Ele vale por 10 minutos." % Account.masked_email(email)
			_note.text = "Não chegou? Olhe no spam e nas abas do Gmail."
			_email_step.visible = false
			_code_step.visible = true
			_code.clear()
			_focus(_code)
		400:
			_note.text = "Confira o e-mail."
		429:
			_note.text = "Muitos códigos para este e-mail. Espere uns minutos."
		_:
			_note.text = "Não deu para mandar agora. Confira a internet e tente de novo."


func _confirm(code: String) -> void:
	if _busy:
		return
	_busy = true
	_note.text = "Conferindo…"
	var reply: Dictionary
	if recover:
		reply = await Account.email_recover(_sent_to, code)
	else:
		reply = await Account.email_protect(code)
	_busy = false
	if not is_inside_tree():
		return
	if reply["code"] == 200:
		Sound.play(Sound.Cue.TAP)
		if recover:
			recovered.emit()
		close()
		return
	_code.clear()
	_focus(_code)
	match reply["code"]:
		409:
			_note.text = "Este e-mail já protege outra conta."
		403:
			_note.text = "Não deu para trocar a conta deste celular. Feche o app e tente de novo."
		400:
			match reply["reason"]:
				"wrong":
					_note.text = "Código errado. Confira e digite de novo."
				"same":
					_note.text = "Esta já é a conta deste celular."
				_:
					_note.text = "Este código não vale mais. Toque em \"Mandar de novo\"."
		_:
			_note.text = "Não deu para conferir agora. Confira a internet e tente de novo."


## Só para não gastar um envio com erro de digitação; quem confere de verdade é
## o servidor.
static func _looks_like_email(email: String) -> bool:
	var at := email.find("@")
	return at > 0 and email.find(".", at) > at + 1 and not email.ends_with(".") and not " " in email


## O foco depois de desenhado: pedir foco a um campo sem retângulo não abre o
## teclado do Android (ver `WelcomePanel.open`).
func _focus(target: Control) -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if target is CodeInput:
		(target as CodeInput).grab()
	else:
		target.grab_focus()
