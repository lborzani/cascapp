extends Node

## Quem dos amigos está com o app aberto, e o que está fazendo.
##
## A lista de amigos é do PocketBase (`Account.friends()`); o "online" é do relay.
## Enquanto o app está em primeiro plano e a conta entrou, este nó mantém um
## socket de **presença** no relay (`relay/src/server.ts`, "presença dos amigos"),
## fora de qualquer sala: é ele que diz aos amigos "estou aqui". O relay só conta
## que B está online para A quando os dois se listam, e a amizade do PocketBase já
## nasce nos dois sentidos, então isso é o mesmo que "são amigos".
##
## O app pergunta (`who`) a cada [constant POLL_SECONDS] só com a gaveta de amigos
## aberta: fechada, ninguém está olhando, e o socket fica parado.
##
## Nada aqui é obrigatório. Sem conta, sem relay ou com a rede fora, os amigos só
## aparecem todos como "Offline".

## A lista ou quem está online mudou.
signal changed
## Um amigo chamou para a sala `code` de `game`.
signal invited(from_id: String, game: StringName, code: String)

const POLL_SECONDS := 5.0
const RETRY_SECONDS := 10.0
const JOIN_SCENE := "res://scenes/join.tscn"
## Telas em que o convite aparece. Fora delas há uma partida, ou uma sala sendo
## aberta, e o aviso no meio seria um convite para abandonar o que se está fazendo.
const INVITE_SCENES: Array[String] = [
	"res://scenes/main_menu.tscn", JOIN_SCENE, "res://scenes/settings.tscn",
]
## Quanto tempo o aviso fica na tela. A sala do outro não espera para sempre.
const INVITE_SECONDS := 60.0
## De quanto em quanto tempo o app pergunta as mensagens não lidas, em primeiro
## plano. `ponytail:` consulta, e não empurrão; o socket de presença pode avisar
## quando a carga do PocketBase incomodar.
const UNREAD_SECONDS := 20.0
## A lista de amigos e os pedidos, de 3 em 3 tiques das não lidas (1 min).
const LISTS_EVERY := 3

## Os amigos da conta, cada um com o perfil público (ver `Account.friends()`).
var list: Array = []
## Pedidos de amizade esperando resposta (ver `Account.friend_requests()`):
## `incoming` para esta conta aceitar, `outgoing` os que ela mandou.
var requests := {"incoming": [], "outgoing": []}
## Id → `{"game", "room", "playing"}` de cada amigo online agora.
var online := {}
## Id do amigo → mensagens que ele mandou e esta conta não leu.
var unread := {}
## O amigo a chamar quando a próxima sala abrir (ver `scenes/pairing.gd`).
var pending_invite := ""
## A gaveta está aberta: perguntar ao relay de tempos em tempos.
var watching := false:
	set(value):
		watching = value
		_poll = 0.0

var _socket: WebSocketPeer = null
var _token := ""
var _hello_sent := false
var _poll := 0.0
var _retry := 0.0
var _unread_poll := 0.0
var _unread_busy := false
var _lists_ticks := 0
## O app foi para o fundo: presença fechada até ele voltar.
var _paused := false


## O endereço do relay. Fora do APK a conta já fica desligada sem
## `CASCAPP_PB_URL`, e com ela a presença.
static func relay_url() -> String:
	var override := OS.get_environment(RelayBridge.URL_ENV)
	return override if not override.is_empty() else RelayBridge.DEFAULT_URL


## O que mostrar embaixo do nome do amigo.
static func status_text(status: Variant) -> String:
	if not status is Dictionary:
		return "Offline"
	var room := str(status.get("room", ""))
	if room.is_empty():
		return "Online"
	var title := Game.game_title(StringName(str(status.get("game", ""))))
	if title.is_empty():
		title = "um jogo"
	if bool(status.get("playing", false)):
		return "Jogando %s" % title
	return "Na sala de espera · %s" % title


func _ready() -> void:
	# Autoload: os testes instanciam o script à parte, sem o `Account`.
	if get_parent() == get_tree().root and has_node(^"/root/Account"):
		Account.signed_in_changed.connect(func(_now: bool) -> void: _retry = 0.0)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_paused = true
			_close()
		NOTIFICATION_APPLICATION_RESUMED:
			_paused = false
			_retry = 0.0


## Amigo online agora, ou `null`.
func status_of(id: String) -> Variant:
	return online.get(id)


## A lista com quem está online primeiro; dentro de cada grupo, a ordem do
## PocketBase (amigos mais antigos primeiro).
func sorted() -> Array:
	var on := list.filter(func(friend: Dictionary) -> bool: return online.has(str(friend.get("id", ""))))
	var off := list.filter(func(friend: Dictionary) -> bool: return not online.has(str(friend.get("id", ""))))
	return on + off


func name_of(id: String) -> String:
	return str(profile_of(id).get("name", ""))


func profile_of(id: String) -> Dictionary:
	for friend: Dictionary in list:
		if str(friend.get("id", "")) == id:
			return friend
	return {}


## O convite vai pelo relay (o aviso na hora) e fica na conversa dos dois.
func invite(to: String, game: StringName, code: String) -> void:
	_send({"t": "invite", "to": to, "game": String(game), "room": code})
	if has_node(^"/root/Account"):
		Account.send_chat(to, {"kind": "invite", "game": String(game), "room": code})


## A sala de `code` abriu: chama o amigo guardado em [member pending_invite], uma
## vez só. Devolve o nome dele, ou vazio quando não havia ninguém a chamar ou a
## presença está fora.
func send_pending_invite(game: StringName, code: String) -> String:
	var to := pending_invite
	pending_invite = ""
	if to.is_empty() or not is_open():
		return ""
	invite(to, game, code)
	var name := name_of(to)
	return name if not name.is_empty() else "seu amigo"


## O que espera o jogador na gaveta: a bolinha da pílula de amigos. Pedidos
## recebidos e mensagens não lidas, menos as de amigo silenciado.
func alerts() -> int:
	var total := (requests["incoming"] as Array).size()
	for id: Variant in unread:
		if not is_muted(str(id)):
			total += int(unread[id])
	return total


func is_muted(id: String) -> bool:
	return bool(profile_of(id).get("muted", false))


## Silencia ou reativa no servidor e, dando certo, na lista daqui.
func set_muted(id: String, muted: bool) -> bool:
	if not await Account.mute_friend(id, muted):
		return false
	profile_of(id)["muted"] = muted
	changed.emit()
	return true


func unread_of(id: String) -> int:
	return int(unread.get(id, 0))


## A conversa com `id` foi aberta: as dele viraram lidas no servidor.
func mark_read(id: String) -> void:
	if unread.erase(id):
		changed.emit()


## Pergunta as não lidas agora. O tique de [constant UNREAD_SECONDS] chama, e a
## gaveta ao abrir.
func refresh_unread() -> void:
	if _unread_busy or not has_node(^"/root/Account") or not Account.signed_in():
		return
	_unread_busy = true
	var counts: Variant = await Account.unread()
	_unread_busy = false
	if counts is Dictionary and counts != unread:
		unread = counts
		changed.emit()


## Aceita ou recusa um pedido recebido e atualiza tudo.
func answer_request(id: String, accept: bool) -> bool:
	var ok := false
	if accept:
		ok = await Account.accept_request(id)
	else:
		ok = await Account.drop_request(id)
	await refresh()
	return ok


## Busca a lista e os pedidos de novo no PocketBase e pergunta ao relay. A gaveta
## chama ao abrir, e o painel de amigos ao adicionar ou remover alguém.
func refresh() -> void:
	if not has_node(^"/root/Account") or not Account.signed_in():
		return
	await _load_lists()
	_poll = 0.0
	if _socket == null:
		_retry = 0.0


## Abre a presença com este token. A autoload chama com o da conta; os testes,
## com o que quiserem.
func connect_presence(url: String, token: String) -> void:
	_close()
	_token = token
	_hello_sent = false
	_socket = WebSocketPeer.new()
	if _socket.connect_to_url(url) != OK:
		_socket = null


func is_open() -> bool:
	return _socket != null and _hello_sent and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func _ids() -> Array:
	return list.map(func(friend: Dictionary) -> String: return str(friend.get("id", "")))


func _process(delta: float) -> void:
	_tick_unread(delta)
	if _socket == null:
		_tick_retry(delta)
		return
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _hello_sent:
				_hello_sent = true
				_send({"t": "presence", "token": _token, "friends": _ids()})
			while _socket.get_available_packet_count() > 0:
				_handle(_socket.get_packet().get_string_from_utf8())
			# Com o aviso de convite na tela também: é a resposta do `who` que o
			# derruba quando a sala fecha (`_drop_dead_invite`).
			if (watching or invite_card() != null) and _socket != null:
				_poll -= delta
				if _poll <= 0.0:
					_poll = POLL_SECONDS
					_send({"t": "who", "friends": _ids()})
		WebSocketPeer.STATE_CLOSED:
			_socket = null
			_retry = RETRY_SECONDS
			if not online.is_empty():
				online.clear()
				changed.emit()


## Só a autoload pergunta sozinha, e só com conta e o app na frente.
func _tick_unread(delta: float) -> void:
	if _paused or get_parent() != get_tree().root:
		return
	_unread_poll -= delta
	if _unread_poll > 0.0:
		return
	_unread_poll = UNREAD_SECONDS
	refresh_unread()
	_sync_push_token()
	# A lista e os pedidos, a cada [constant LISTS_EVERY] tiques: quem aceitou o
	# nosso pedido, e o pedido novo que chegou, aparecem sem abrir a gaveta.
	_lists_ticks += 1
	if _lists_ticks >= LISTS_EVERY:
		_lists_ticks = 0
		refresh()


var _push_sent := ""


## O token do Firebase deste aparelho (plugin `GodotApp`) vai para a conta, para a
## notificação de mensagem com o app fechado. Uma vez por token e por abertura;
## sem plugin (editor, desktop) ou sem conta, nada. O Firebase demora a dar o
## primeiro token: o tique seguinte pergunta de novo.
func _sync_push_token() -> void:
	if not OS.has_feature("template") or not Engine.has_singleton("GodotApp") or not Account.signed_in():
		return
	var token: String = Engine.get_singleton("GodotApp").pushToken()
	if token.is_empty() or token == _push_sent:
		return
	_push_sent = token
	if not await Account.push_token(token):
		_push_sent = ""


## Só a autoload reconecta sozinha, e só com conta, relay e o app na frente.
func _tick_retry(delta: float) -> void:
	if _paused or not has_node(^"/root/Account") or get_parent() != get_tree().root:
		return
	if not Account.signed_in() or not Net.relay_available():
		return
	_retry -= delta
	if _retry > 0.0:
		return
	_retry = RETRY_SECONDS
	if list.is_empty():
		await _load_lists()
	if _socket == null and not _paused:
		connect_presence(relay_url(), Account.token)


## A lista e os pedidos, do PocketBase. Resposta que falhou deixa o que havia.
func _load_lists() -> void:
	var fresh: Variant = await Account.friends()
	var pending: Variant = await Account.friend_requests()
	if fresh is Array:
		var before := _ids()
		list = fresh
		# O relay só mostra B online para A quando os dois se listam, e a lista
		# dele é a que este aparelho mandou por último. Amigo novo (pedido aceito
		# do outro lado) sem este aviso ficava "Offline" até alguém abrir a gaveta.
		if _ids() != before:
			_send({"t": "who", "friends": _ids()})
	if pending is Dictionary:
		requests = pending
	if fresh is Array or pending is Dictionary:
		changed.emit()


func _handle(text: String) -> void:
	var message: Variant = JSON.parse_string(text)
	if not message is Dictionary:
		return
	match str(message.get("t", "")):
		"friends":
			var now := {}
			for entry: Variant in message.get("online", []):
				if entry is Dictionary:
					now[str(entry.get("id", ""))] = entry
			online = now
			changed.emit()
			_drop_dead_invite()
		"invited":
			var from := str(message.get("from", ""))
			var game := StringName(str(message.get("game", "")))
			var code := str(message.get("room", ""))
			if from.is_empty() or code.is_empty():
				return
			invited.emit(from, game, code)
			if get_parent() == get_tree().root:
				show_invite(from, game, code)


# --- convite recebido ------------------------------------------------------------

var _invite_layer: CanvasLayer = null
## De quem e para qual sala é o aviso na tela.
var _invite_from := ""
var _invite_code := ""


## Quem chamou fechou a sala (ou ela encheu, ou ele saiu do app): o aviso some,
## em vez de levar a uma sala que não existe mais.
func _drop_dead_invite() -> void:
	if invite_card() != null and not invite_live(_invite_from, _invite_code):
		dismiss_invite()


## O aviso "Fulano te chamou", por cima da tela. Só nas telas fora de partida; um
## segundo convite troca o primeiro.
func show_invite(from: String, game: StringName, code: String) -> void:
	var scene := get_tree().current_scene
	if scene == null or not INVITE_SCENES.has(scene.scene_file_path):
		return
	# Com a versão nova obrigatória na tela, Entrar levaria à sala por fora dela.
	if scene.get_children().any(func(child: Node) -> bool: return child is UpdateGate):
		return
	dismiss_invite()
	_invite_from = from
	_invite_code = code
	# Pergunta já: a resposta confirma a sala, e as seguintes derrubam o aviso
	# quando ela fechar.
	_poll = 0.0
	_invite_layer = CanvasLayer.new()
	_invite_layer.layer = 50
	add_child(_invite_layer)
	var profile := profile_of(from)
	var card := InviteCard.new()
	card.friend_name = str(profile.get("name", "")) if not profile.is_empty() else "Um amigo"
	card.photo = Account.avatar_of(from, str(profile.get("avatar", "")))
	card.game_title = Game.game_title(game)
	card.accepted.connect(func() -> void:
		dismiss_invite()
		Game.join_info = {"game": game, "code": code}
		get_tree().change_scene_to_file(JOIN_SCENE)
	)
	card.declined.connect(dismiss_invite)
	_invite_layer.add_child(card)
	get_tree().create_timer(INVITE_SECONDS).timeout.connect(func() -> void:
		if is_instance_valid(card):
			dismiss_invite()
	)
	Sound.play(Sound.Cue.TAP)


## O convite de `from` para a sala `code` ainda vale: quem chamou está sentado
## nela e a mesa ainda espera gente. Sala fechada, mesa cheia ou quem chamou fora
## do app derrubam o convite. Sem rota nova no relay: é o mesmo `who` da gaveta,
## que diz onde cada amigo está sentado.
func invite_live(from: String, code: String) -> bool:
	var status: Variant = status_of(from)
	return status is Dictionary and str(status.get("room", "")) == code and not bool(status.get("playing", false))


func invite_card() -> InviteCard:
	if _invite_layer == null or not is_instance_valid(_invite_layer):
		return null
	return _invite_layer.get_child(0) as InviteCard if _invite_layer.get_child_count() > 0 else null


func dismiss_invite() -> void:
	if _invite_layer != null and is_instance_valid(_invite_layer):
		_invite_layer.queue_free()
	_invite_layer = null


func _send(message: Dictionary) -> void:
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(message))


func _close() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
	if not online.is_empty():
		online.clear()
		changed.emit()
