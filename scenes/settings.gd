extends Control

## Ajustes: o que vale para o app inteiro, e não para uma partida.
##
## O nome do jogador e os dois interruptores de som e vibração. A tela existe
## antes de ter muito o que ajustar de propósito — o nome precisa de um lugar
## óbvio, e "óbvio" é uma engrenagem no canto da tela inicial, não um campo
## escondido dentro de outra coisa.
##
## O **nome** salva ao sair do campo e ao tocar em "Salvar", e não a cada tecla:
## gravar em disco a cada letra digitada é dez escritas para uma decisão. Os
## **interruptores** salvam na hora, porque um interruptor não tem momento de
## confirmar — ele já é a decisão, e quem desligou o som e saiu pelo "Voltar"
## esperaria encontrá-lo desligado.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const JOIN_SCENE := "res://scenes/join.tscn"

var _sound_switch: SwitchRow = null
var _haptics_switch: SwitchRow = null


func _ready() -> void:
	# Window.theme não desce para os Controls; o tema entra pela raiz da cena.
	theme = AppTheme.shared()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)

	%NameEdit.max_length = Prefs.NAME_LIMIT
	# Campo vazio quando ainda não há escolha, com o padrão só no placeholder: um
	# "Você" dentro do campo parece nome digitado, e ninguém troca o que já
	# parece escolhido.
	%NameEdit.text = Prefs.player_name() if Prefs.has_name() else ""
	%NameEdit.placeholder_text = Prefs.DEFAULT_NAME
	%NameEdit.text_submitted.connect(func(_text: String): _save())
	%NameEdit.focus_exited.connect(_save)
	%SaveButton.pressed.connect(_save_and_leave)

	%AppBar.title = "Você"
	# Aba é lugar, e de um lugar não se volta: quem quer outro lugar toca noutra aba.
	%AppBar.leading = -1

	%Tabs.current = AppTabs.YOU
	if not Net.relay_available():
		%Tabs.disabled = [AppTabs.ONLINE] as Array[StringName]
	%Tabs.picked.connect(_go_tab)

	_sound_switch = SwitchRow.new()
	_sound_switch.setup("Som", Prefs.sound_on())
	_sound_switch.switched.connect(_toggle_sound)
	%Switches.add_child(_sound_switch)

	_haptics_switch = SwitchRow.new()
	_haptics_switch.setup("Vibração", Prefs.haptics_on())
	_haptics_switch.switched.connect(_toggle_haptics)
	%Switches.add_child(_haptics_switch)

	%StatusLabel.text = _status_text()
	_update_preview()


func _go_tab(route: StringName) -> void:
	_save()
	Sound.play(Sound.Cue.TAP)
	match route:
		AppTabs.GAMES:
			get_tree().change_scene_to_file(MENU_SCENE)
		AppTabs.ONLINE:
			get_tree().change_scene_to_file(JOIN_SCENE)


## Os dois interruptores gravam **na hora**, e não no "Salvar".
##
## O botão de salvar é do nome, que é um campo de texto e precisa de um momento
## de confirmar. Um interruptor não tem esse momento: ele já é a decisão, e quem
## desligou o som e saiu pelo "Voltar" esperaria encontrá-lo desligado.
##
## O de som toca ao ser **ligado**. É a única forma de responder "ligado como?"
## sem mandar o jogador abrir uma partida para descobrir.
func _toggle_sound(value: bool) -> void:
	Prefs.set_sound(value)
	if value:
		Sound.play(Sound.Cue.CASH)


func _toggle_haptics(value: bool) -> void:
	Prefs.set_haptics(value)
	# A vibração só se prova vibrando, e ela não sai do `Sound` sem um sinal que a
	# tenha. O toque é o mais curto dos quatro que vibram.
	if value:
		Sound.play(Sound.Cue.TAP)


## Que build é este e o que ele consegue fazer.
##
## Estava no rodapé da tela inicial, sob a lista de jogos. Saiu de lá porque é
## diagnóstico: responde "por que não tem sala nenhuma?" e "por que o botão de
## câmera não aparece?", que são perguntas que se fazem **depois** de estranhar
## alguma coisa — e o rodapé da primeira tela é o lugar mais caro do app para uma
## resposta que quase ninguém procura.
func _status_text() -> String:
	var parts := PackedStringArray()
	parts.append("Versão %s" % AppVersion.text())
	parts.append("On-line: %s" % ("sim" if Net.relay_available() else "não"))
	parts.append("NFC: %s" % ("sim" if Pairing.nfc.is_available() else "não"))
	parts.append("Câmera: %s" % ("sim" if Pairing.qr_scanner.is_available() else "não"))
	return "   •   ".join(parts)


func _save() -> void:
	Prefs.set_player_name(%NameEdit.text)
	_update_preview()


func _save_and_leave() -> void:
	_save()
	_leave()


## O que os outros vão ver, escrito com o nome já aplicado. Um campo de texto não
## diz onde o valor aparece; esta linha diz.
func _update_preview() -> void:
	%Preview.text = "Nas partidas você aparece como %s." % Prefs.player_name()
	# A bolacha é a mesma que os outros vão ver na mesa: mostrar o nome e a bolacha
	# juntos responde "como eu apareço" sem o jogador ter de abrir uma partida.
	%Avatar.player_name = Prefs.player_name()


## O gesto de voltar é o botão "Voltar", e não o "Salvar": quem sai pelo gesto
## sai sem confirmar o campo de texto, como sairia pelo botão. Os interruptores
## já gravaram sozinhos, então o que se perde é no máximo um nome digitado pela
## metade e nunca confirmado.
func go_back() -> void:
	_leave()


func _leave() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
