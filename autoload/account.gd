extends Node

## A conta do jogador no PocketBase do servidor de casa (`pocketbase/`).
##
## Anônima e sem tela: o e-mail sintético e a senha são **derivados do
## aparelho** (`OS.get_unique_id()`, o `ANDROID_ID` no Android) por hash. No
## primeiro uso o app cria a conta com eles; daí em diante só entra.
##
## Derivados, e não sorteados e guardados: desinstalar apaga o `user://`, e com
## a credencial guardada lá cada reinstalação nascia uma conta nova. O
## `ANDROID_ID` sobrevive à reinstalação (muda com reset de fábrica e com outra
## chave de assinatura), então reinstalar volta para a mesma conta. O id em si
## nunca sai do aparelho — só o hash.
## O nome é o da tela "Você" — salvar lá sobe para a conta.
##
## Nada aqui é obrigatório para jogar. Servidor fora do ar, sem rede, resposta
## estranha: `signed_in()` fica falso, o app segue igual, e uma nova tentativa
## acontece a cada `RETRY_SECONDS` e quando o app volta ao primeiro plano.

signal signed_in_changed(now: bool)
## A foto deste aparelho mudou: escolhida agora ou baixada da conta.
signal avatar_changed
## Chegou a foto de outra conta pedida em [method avatar_of].
signal remote_avatar_loaded
## O saldo ou os itens mudaram: entrada, bônus, prêmio ou compra.
signal wallet_changed
## A lista de missões mudou (chegou, avançou ou uma foi resgatada).
signal missions_changed
## A caixa de presentes mudou (chegou, foi aberto ou mandei um presentinho).
signal gifts_changed

## O PocketBase (`/api`) e a busca (`/search`) da Pi, pelo túnel do Cloudflare
## (borda em São Paulo). Até a 1.56 era `homeserver.tailb8b7e1.ts.net:8443/cascapp`,
## pelo Funnel, com ingresso em Nova York; esse endereço segue no ar para as
## versões antigas (ver `pocketbase/README.md`).
const DEFAULT_URL := "https://api.cascapp.com.br"
const EMAIL_DOMAIN := "anon.cascapp.invalid"
const RETRY_SECONDS := 60.0
## Um pedido a mais que isto é servidor fora do ar, e não lentidão.
const TIMEOUT_SECONDS := 8.0
## A foto deste aparelho, já comprimida. Vale antes de a conta ter recebido.
const AVATAR_CACHE := "user://avatar.webp"

var token := ""
## Só para os testes: troca o id do aparelho, para cada execução ter a própria
## conta num PocketBase que guarda as anteriores.
var device_seed := ""
var user_id := ""
## O nome do arquivo da foto na conta (`avatar` do registro); vazio sem foto.
var avatar_file := ""
## O Elo do xadrez desta conta, como a última entrada disse. 0 sem Elo.
var elo := 0
## O código de amigo desta conta, como a última entrada disse; vazio sem conta.
var friend_code := ""
## O e-mail que protege esta conta (`pocketbase/pb_hooks/conta.pb.js`); vazio
## sem proteção.
var contact_email := ""
## O saldo de moedas, como a última resposta disse; -1 antes da primeira.
var coins := -1
## Os itens pagos que esta conta comprou (catálogo na coleção `shop_items` do servidor).
var owned: Array = []
## O bônus do dia que entrou e ainda não foi mostrado. Quem mostra zera.
var daily_notice := 0
## O visual equipado (`Cosmetics`). Começa pela cópia do aparelho; a conta
## confirma na entrada.
var look: Dictionary = Prefs.look()
## id → preço, da loja do servidor; vazio até [method fetch_prices] responder.
var prices := {}
## Todo item que só se equipa tendo (à venda, fora de venda ou exclusivo), e os
## exclusivos, que só saem por missão. Vazios até [method fetch_prices].
var paid: Array = []
var exclusive: Array = []
## As missões valendo agora (`GET /api/cascapp/missions`) e os eventos no ar;
## vazias até [method fetch_missions] responder.
var missions: Array = []
var events: Array = []
## Missões que o prêmio de uma partida acabou de completar e ainda não foram
## mostradas. Quem mostra esvazia.
var missions_notice: Array = []
## Os presentes fechados que chegaram (`GET /api/cascapp/gifts`), os amigos que
## já ganharam o meu presentinho hoje e quanto ele vale.
var gifts: Array = []
var gifts_sent_today: Array = []
var gift_daily_coins := 10
## O nome que a conta tem no servidor, como a última resposta disse.
var _name := ""
## O dia de Brasília do último pedido de bônus, para não pedir a cada volta ao app.
var _daily_day := ""
var _rewarding := false
## O `updated` da carteira aplicada por último (ver `_take_wallet`).
var _wallet_at := ""
var _busy := false
var _local_texture: Texture2D = null
## Nome do arquivo → foto de outra conta (`null` enquanto baixa).
var _remote := {}
var _retry: Timer = null


## Fora do APK (editor, suítes headless) a conta só liga com `CASCAPP_PB_URL`
## apontando para um PocketBase de teste: rodar a CI não pode criar conta no
## servidor de verdade.
static func base_url() -> String:
	if OS.has_environment("CASCAPP_PB_URL"):
		return OS.get_environment("CASCAPP_PB_URL")
	return "" if OS.has_feature("editor") else DEFAULT_URL


func _ready() -> void:
	_retry = Timer.new()
	_retry.wait_time = RETRY_SECONDS
	_retry.one_shot = true
	_retry.timeout.connect(sign_in)
	add_child(_retry)
	if not base_url().is_empty():
		sign_in()


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_IN or base_url().is_empty():
		return
	# Adiado: durante a notificação o Godot não deixa este nó ganhar filhos, e
	# o `HTTPRequest` do pedido nascia fora da árvore ("Parent node is busy
	# setting up children"). A entrada falhava e só voltava 60 s depois.
	if not signed_in():
		sign_in.call_deferred()
	else:
		# Quem volta ao app pela notificação de um presente já o vê na caixa.
		fetch_gifts.call_deferred()
		if _daily_day != br_day(int(Time.get_unix_time_from_system())):
			# O app ficou aberto (ou em segundo plano) até virar o dia.
			claim_daily.call_deferred()


func signed_in() -> bool:
	return not token.is_empty()


## Cria a conta se ainda não existe e entra. Devolve se entrou.
func sign_in() -> bool:
	if _busy or base_url().is_empty():
		return signed_in()
	_busy = true
	var credentials := _credentials()
	var code := await _authenticate(credentials)
	if code == 400:
		# Recusada: a conta deste aparelho ainda não existe — primeiro uso, ou
		# apagada no painel. Nasce agora, com a mesma credencial.
		if await _create(credentials):
			code = await _authenticate(credentials)
	var ok := code == 200
	_busy = false
	if ok and Prefs.has_name() and _name != Prefs.player_name():
		# O nome mudou enquanto o servidor estava fora: a conta alcança agora.
		await push_name(Prefs.player_name())
	var has_local := FileAccess.file_exists(AVATAR_CACHE)
	if ok and (Prefs.avatar_pending() or (has_local and avatar_file.is_empty())):
		# Idem para a foto escolhida com o servidor fora — ou para a conta que
		# renasceu sem a foto que o aparelho tem.
		await push_avatar()
	elif ok and not avatar_file.is_empty() and not has_local:
		# A conta tem foto e o aparelho não: reinstalação. Baixa a de lá.
		await _fetch_own_avatar()
	if ok:
		# Partidas que terminaram com o servidor fora sobem agora.
		push_reviews()
		push_matches()
		push_rewards()
		claim_daily()
		fetch_missions()
		fetch_gifts()
	if not ok:
		_retry.start()
	return ok


## Sobe o nome da tela "Você". Sem conta ainda, não há o que fazer: o nome vai
## junto quando ela for criada, e a próxima entrada não sobrescreve nada.
func push_name(name: String) -> bool:
	if not signed_in():
		return false
	var reply := await _call(HTTPClient.METHOD_PATCH, "/api/collections/users/records/" + user_id, {"name": name})
	if reply["code"] == 200:
		_name = name
	return reply["code"] == 200


# --- amigos ---------------------------------------------------------------------
#
# Rotas de `pocketbase/pb_hooks/amigos.pb.js`. Adicionar pelo código manda um
# pedido; a amizade nasce quando o outro aceita, ou na hora se ele já tinha pedido.


## Os amigos desta conta, cada um com o perfil público
## (`{"id", "name", "avatar", "friend_code", "elo_chess", "games_chess"}`).
## `null` quando não deu para perguntar — diferente de lista vazia.
func friends() -> Variant:
	if not signed_in():
		return null
	var reply := await _call(HTTPClient.METHOD_GET, "/api/cascapp/friends", {})
	var data: Variant = reply["data"]
	if reply["code"] != 200 or not data is Dictionary or not data.get("items") is Array:
		return null
	return data["items"]


## Pede amizade pelo código. `{"code": HTTP, "data": perfil ou erro}`: 200 com
## `data.status` "requested" (espera o outro) ou "friends" (já eram, ou o outro
## tinha pedido); 404 código que não existe, 400 o próprio código, 429 pedidos
## demais esperando, 0 sem conta ou sem servidor.
func add_friend(code: String) -> Dictionary:
	if not signed_in():
		return {"code": 0, "data": null}
	return await _call(HTTPClient.METHOD_POST, "/api/cascapp/friends/" + code.uri_encode(), {})


func remove_friend(id: String) -> bool:
	if not signed_in():
		return false
	var reply := await _call(HTTPClient.METHOD_DELETE, "/api/cascapp/friends/" + id.uri_encode(), {})
	return reply["code"] == 204


## Silencia (ou reativa) as notificações das mensagens de um amigo. Só do lado
## desta conta.
func mute_friend(id: String, muted: bool) -> bool:
	if not signed_in():
		return false
	var reply := await _call(HTTPClient.METHOD_PUT, "/api/cascapp/friends/%s/mute" % id.uri_encode(), {"muted": muted})
	return reply["code"] == 204


## Bloqueia: desfaz a amizade e os pedidos entre os dois, e o outro não consegue
## mais pedir (`pocketbase/pb_hooks/amigos.pb.js`).
func block(id: String) -> bool:
	if not signed_in():
		return false
	var reply := await _call(HTTPClient.METHOD_POST, "/api/cascapp/blocks/" + id.uri_encode(), {})
	return reply["code"] == 204


## Desbloqueia. A amizade não volta sozinha.
func unblock(id: String) -> bool:
	if not signed_in():
		return false
	var reply := await _call(HTTPClient.METHOD_DELETE, "/api/cascapp/blocks/" + id.uri_encode(), {})
	return reply["code"] == 204


## As contas bloqueadas, com o perfil público. `null` quando não deu para
## perguntar.
func blocks() -> Variant:
	if not signed_in():
		return null
	var reply := await _call(HTTPClient.METHOD_GET, "/api/cascapp/blocks", {})
	var data: Variant = reply["data"]
	if reply["code"] != 200 or not data is Dictionary or not data.get("items") is Array:
		return null
	return data["items"]


## Os pedidos esperando resposta: `{"incoming": [...], "outgoing": [...]}`, cada
## um `{"id", "created", "profile"}`. `null` quando não deu para perguntar.
func friend_requests() -> Variant:
	if not signed_in():
		return null
	var reply := await _call(HTTPClient.METHOD_GET, "/api/cascapp/friends/requests", {})
	var data: Variant = reply["data"]
	if reply["code"] != 200 or not data is Dictionary or not data.get("incoming") is Array or not data.get("outgoing") is Array:
		return null
	return data


## Aceita o pedido recebido `id`. Verdadeiro se viraram amigos.
func accept_request(id: String) -> bool:
	if not signed_in():
		return false
	var reply := await _call(HTTPClient.METHOD_POST, "/api/cascapp/friends/requests/%s/accept" % id.uri_encode(), {})
	return reply["code"] == 200


## Recusa um pedido recebido ou cancela um enviado.
func drop_request(id: String) -> bool:
	if not signed_in():
		return false
	var reply := await _call(HTTPClient.METHOD_DELETE, "/api/cascapp/friends/requests/" + id.uri_encode(), {})
	return reply["code"] == 204


## O perfil de um amigo: `{"profile", "stats", "recent"}` (ver a rota em
## `pocketbase/pb_hooks/amigos.pb.js`). `stats` é jogo → `{played, won, lost,
## draw}`; `recent`, as 20 últimas partidas no formato do histórico. `null`
## quando não deu para perguntar ou a conta não é mais amiga.
func friend_profile(id: String) -> Variant:
	if not signed_in():
		return null
	var reply := await _call(HTTPClient.METHOD_GET, "/api/cascapp/friends/%s/profile" % id.uri_encode(), {})
	var data: Variant = reply["data"]
	if reply["code"] != 200 or not data is Dictionary or not data.get("stats") is Dictionary or not data.get("recent") is Array:
		return null
	return data


# --- conversa com amigos ---------------------------------------------------------
#
# Rotas de `pocketbase/pb_hooks/conversa.pb.js`. Cada mensagem é
# `{"id", "from", "kind", "text", "emote", "game", "room", "at"}`, com `kind`
# "text", "emote" ou "invite" e `at` em tempo Unix.


## As últimas mensagens com `friend`, da mais antiga à mais nova. Ler marca as
## recebidas como lidas. `null` quando não deu para perguntar.
func chat(friend: String) -> Variant:
	if not signed_in():
		return null
	var reply := await _call(HTTPClient.METHOD_GET, "/api/cascapp/chat/" + friend.uri_encode(), {})
	var data: Variant = reply["data"]
	if reply["code"] != 200 or not data is Dictionary or not data.get("items") is Array:
		return null
	return data["items"]


## Manda `body` (`{"kind": "text", "text"}`, `{"kind": "emote", "emote"}` ou
## `{"kind": "invite", "game", "room"}`). `{"code": HTTP, "data": mensagem}`: 200
## foi, 400 inválida, 404 não é mais amigo, 429 rápido demais, 0 sem servidor.
func send_chat(friend: String, body: Dictionary) -> Dictionary:
	if not signed_in():
		return {"code": 0, "data": null}
	return await _call(HTTPClient.METHOD_POST, "/api/cascapp/chat/" + friend.uri_encode(), body)


## O token do Firebase deste aparelho, para a notificação de mensagem com o app
## fechado. Verdadeiro se o servidor guardou.
func push_token(token: String) -> bool:
	if not signed_in() or token.is_empty():
		return false
	var reply := await _call(HTTPClient.METHOD_PUT, "/api/cascapp/push-token", {"token": token})
	return reply["code"] == 204


## Id do amigo → mensagens não lidas. `null` quando não deu para perguntar.
func unread() -> Variant:
	if not signed_in():
		return null
	var reply := await _call(HTTPClient.METHOD_GET, "/api/cascapp/chat/unread", {})
	var data: Variant = reply["data"]
	if reply["code"] != 200 or not data is Dictionary or not data.get("counts") is Dictionary:
		return null
	return data["counts"]


# --- partidas para o perfil dos amigos -------------------------------------------
#
# Toda partida com resultado sobe para `matches`, como a revisão do xadrez: vale
# primeiro no aparelho (`Prefs`, marca `synced`) e sobe quando der.

var _pushing_matches := false


## Mesma regra da `push_reviews`: 200 subiu, 400 já estava lá (ou nunca vai
## entrar); as duas saem da fila. Qualquer outra resposta para tudo. Uma subida
## por vez: o `sign_in` e o fim de partida podem chamar juntos, e quem chega
## com outra em curso espera ela acabar e confere a fila de novo.
func push_matches() -> void:
	while _pushing_matches:
		await get_tree().process_frame
	if not signed_in():
		return
	_pushing_matches = true
	for game: Dictionary in Prefs.pending_matches():
		var reply := await _call(HTTPClient.METHOD_POST, "/api/collections/matches/records", MatchLog.server_body(game, user_id))
		if reply["code"] != 200 and reply["code"] != 400:
			break
		Prefs.mark_synced(int(game["at"]))
	_pushing_matches = false


# --- revisão no servidor --------------------------------------------------------
#
# Cada partida de xadrez que termina vira um pedido em `chess_reviews`, que o
# worker do servidor de casa preenche (`pocketbase/pb_migrations/
# 1760800000_revisoes_xadrez.js`). Como o nome e a foto: vale primeiro no
# aparelho (`Prefs`, marca `uploaded`) e sobe quando der.


## Sobe as partidas pendentes, da mais recente para a mais antiga. 200 subiu;
## 400 é a mesma partida que já tinha subido (resposta perdida) ou uma que o
## servidor nunca vai aceitar — repetir não muda nada, então as duas saem da
## fila. Qualquer outra resposta (sem rede, 429, servidor fora) para tudo, e a
## próxima entrada ou partida tenta de novo.
func push_reviews() -> void:
	if not signed_in():
		return
	for game: Dictionary in Prefs.pending_uploads():
		var reply := await _call(HTTPClient.METHOD_POST, "/api/collections/chess_reviews/records", review_body(game, user_id))
		if reply["code"] != 200 and reply["code"] != 400:
			return
		Prefs.mark_uploaded(int(game["at"]))


## A revisão da partida `at` no servidor: `{"status", "analysis"}`, com `status`
## "" (pendente), "done", "failed" ou "missing" (não subiu). Vazio sem conta ou
## sem resposta. Quem decide o que fazer é `GameReview.server_step`.
func fetch_review(at: int) -> Dictionary:
	if not signed_in():
		return {}
	var filter := ('owner = "%s" && played_at = %d' % [user_id, at]).uri_encode()
	var reply := await _call(HTTPClient.METHOD_GET, "/api/collections/chess_reviews/records?filter=%s&perPage=1&skipTotal=1" % filter, {})
	if reply["code"] != 200 or not reply["data"] is Dictionary:
		return {}
	var items: Array = reply["data"].get("items", [])
	if items.is_empty():
		return {"status": "missing", "analysis": []}
	var record: Dictionary = items[0]
	var analysis: Variant = record.get("analysis")
	return {"status": str(record.get("status", "")), "analysis": analysis if analysis is Array else []}


## Sobe uma partida do histórico agora, fora da fila (a de antes da revisão no
## servidor, que nunca entrou nela). Verdadeiro se ela está lá: 200, ou 400 da
## que já tinha subido.
func upload_review(game: Dictionary) -> bool:
	if not signed_in():
		return false
	var reply := await _call(HTTPClient.METHOD_POST, "/api/collections/chess_reviews/records", review_body(game, user_id))
	if reply["code"] != 200 and reply["code"] != 400:
		return false
	Prefs.mark_uploaded(int(game["at"]))
	return true


## A análise do servidor da partida `game` (`Prefs.history`), pela regra de
## `GameReview.server_step`: pronta volta na hora; pendente, espera; a que nunca
## subiu sobe agora e espera junto. Vazio quando a revisão deve ser no aparelho.
## `alive` falso interrompe a espera (a tela fechou, a fila andou).
func server_review(game: Dictionary, alive: Callable) -> Array:
	if game.is_empty() or not signed_in():
		return []
	var at := int(game.get("at", 0))
	var queued: bool = game.get("uploaded", true) == false
	if queued:
		# Pode ter terminado sem rede: tenta subir de novo enquanto espera.
		push_reviews()
	var since := Time.get_ticks_msec()
	while true:
		var reply := await fetch_review(at)
		if not alive.call():
			return []
		if reply.get("status") == "missing" and not queued:
			queued = await upload_review(game)
			if not alive.call():
				return []
		match GameReview.server_step(reply, queued, (Time.get_ticks_msec() - since) / 1000.0):
			GameReview.Source.SERVER:
				return reply["analysis"]
			GameReview.Source.LOCAL:
				return []
		await get_tree().create_timer(GameReview.SERVER_POLL_S).timeout
		if not alive.call():
			return []
	return []


## O registro de `chess_reviews` de uma partida do histórico (`Prefs.history`).
static func review_body(game: Dictionary, owner: String) -> Dictionary:
	return {
		"owner": owner,
		"moves": ChessRules.new().uci_line(game["moves"]),
		"side": "white" if int(game.get("side", Board.Side.WHITE)) == Board.Side.WHITE else "black",
		"hotseat": bool(game.get("hotseat", false)),
		"against": str(game.get("against", "")).left(60),
		"played_at": int(game["at"]),
	}


# --- moedas ---------------------------------------------------------------------
#
# Rotas de `pocketbase/pb_hooks/loja.pb.js`. O saldo é do servidor: o app só
# mostra o que a última resposta disse. Cada rota devolve a carteira inteira.


## O dia de Brasília (UTC-3) de um instante Unix, "AAAA-MM-DD", como o servidor
## conta o bônus diário.
static func br_day(unix: int) -> String:
	return Time.get_date_string_from_unix_time(unix - 3 * 3600)


## Pede o bônus do dia. Quando ele entra, [member daily_notice] guarda quanto,
## para o menu avisar.
func claim_daily() -> void:
	if not signed_in():
		return
	_daily_day = br_day(int(Time.get_unix_time_from_system()))
	var reply := await _call(HTTPClient.METHOD_POST, "/api/cascapp/daily", {})
	if reply["code"] != 200 or not reply["data"] is Dictionary:
		_daily_day = ""
		return
	daily_notice += int(reply["data"].get("granted", 0))
	_take_wallet(reply["data"])


## Uma partida terminou contra bot ou online, com `result` "win", "draw" ou
## "loss". Entra na fila do aparelho e sobe agora se der. Devolve as moedas pagas
## nesta subida: 0 sem conta (fica na fila), no teto do dia, ou com a partida
## (`key`) já contada. Fora do APK sem `CASCAPP_PB_URL` não faz nada.
func reward(game: StringName, result: String, key: String) -> int:
	if base_url().is_empty() or not Prefs.queue_reward({"game": String(game), "result": result, "key": key}):
		return 0
	return await push_rewards()


## Sobe a fila de prêmios, da mais antiga para a mais nova. 200 pagou; 400 é
## pedido que o servidor nunca vai aceitar e sai da fila. Qualquer outra resposta
## para tudo, e a próxima entrada ou partida tenta de novo.
func push_rewards() -> int:
	if not signed_in() or _rewarding:
		return 0
	_rewarding = true
	var granted := 0
	while true:
		# Relida a cada volta: a partida que terminou durante a subida entra junto.
		var queue := Prefs.pending_rewards()
		if queue.is_empty():
			break
		var entry: Dictionary = queue[0]
		var reply := await _call(HTTPClient.METHOD_POST, "/api/cascapp/reward", {"game": entry["game"], "result": entry["result"]})
		if reply["code"] == 200 and reply["data"] is Dictionary:
			granted += int(reply["data"].get("granted", 0))
			_take_wallet(reply["data"])
			var done: Variant = reply["data"].get("missions_done")
			if done is Array and not done.is_empty():
				missions_notice.append_array(done)
				fetch_missions()
		elif reply["code"] != 400:
			break
		Prefs.drop_reward(str(entry["key"]))
	_rewarding = false
	return granted


## Os preços da loja. Falso sem resposta.
func fetch_prices() -> bool:
	var reply := await _call(HTTPClient.METHOD_GET, "/api/cascapp/shop", {})
	if reply["code"] != 200 or not reply["data"] is Dictionary:
		return false
	var data: Dictionary = reply["data"]
	prices = data["items"] if data.get("items") is Dictionary else {}
	paid = data["paid"] if data.get("paid") is Array else prices.keys()
	exclusive = data["exclusive"] if data.get("exclusive") is Array else []
	wallet_changed.emit()
	return true


## Se o item pode ser equipado: comprado, ou grátis (fora do catálogo pago).
## Sem o catálogo ainda, só o comprado.
func owns(item: String) -> bool:
	return item in owned or (not paid.is_empty() and item not in paid)


## As missões valendo agora. Falso sem resposta.
func fetch_missions() -> bool:
	if not signed_in():
		return false
	var reply := await _call(HTTPClient.METHOD_GET, "/api/cascapp/missions", {})
	if reply["code"] != 200 or not reply["data"] is Dictionary:
		return false
	var data: Dictionary = reply["data"]
	missions = data["missions"] if data.get("missions") is Array else []
	events = data["events"] if data.get("events") is Array else []
	missions_changed.emit()
	return true


## Quantas missões estão completas e esperando o resgate.
func missions_ready() -> int:
	return missions.filter(func(m: Dictionary) -> bool:
		return not m.get("claimed", false) and m.get("progress", 0) >= m.get("target", 1)
	).size()


## A caixa de presentes. Falso sem resposta.
func fetch_gifts() -> bool:
	if not signed_in():
		return false
	var reply := await _call(HTTPClient.METHOD_GET, "/api/cascapp/gifts", {})
	if reply["code"] != 200 or not reply["data"] is Dictionary:
		return false
	var data: Dictionary = reply["data"]
	gifts = data["gifts"] if data.get("gifts") is Array else []
	gifts_sent_today = data["sent_today"] if data.get("sent_today") is Array else []
	gift_daily_coins = int(data.get("daily_coins", gift_daily_coins))
	gifts_changed.emit()
	return true


## Manda `item` de presente ao amigo `to`, pago com as minhas moedas. O código
## HTTP: 200 mandou, 402 sem moedas, 409 o amigo já tem, 404 sem amizade ou item
## fora de venda; 0 sem conta ou sem resposta.
func send_gift(to: String, item: String) -> int:
	if not signed_in():
		return 0
	var reply := await _call(HTTPClient.METHOD_POST, "/api/cascapp/gifts", {"to": to, "item": item})
	if reply["code"] == 200 and reply["data"] is Dictionary:
		_take_wallet(reply["data"])
	return reply["code"]


## O presentinho do dia para o amigo `to`. O código HTTP: 200 mandou, 409 já
## mandei hoje, 429 ele já ganhou demais hoje, 404 sem amizade; 0 sem resposta.
func send_daily_gift(to: String) -> int:
	if not signed_in():
		return 0
	var reply := await _call(HTTPClient.METHOD_POST, "/api/cascapp/gifts/daily", {"to": to})
	if reply["code"] in [200, 409] and to not in gifts_sent_today:
		gifts_sent_today.append(to)
		gifts_changed.emit()
	return reply["code"]


## Abre o presente `id`. Devolve `{item, coins, items, message}` do que veio
## (`items` e `message` só no kit do admin), ou `{}` se não deu.
func open_gift(id: String) -> Dictionary:
	if not signed_in():
		return {}
	var reply := await _call(HTTPClient.METHOD_POST, "/api/cascapp/gifts/%s/open" % id.uri_encode(), {})
	if reply["code"] == 404:
		gifts = gifts.filter(func(gift: Dictionary) -> bool: return gift.get("id") != id)
		gifts_changed.emit()
	if reply["code"] != 200 or not reply["data"] is Dictionary:
		return {}
	_take_wallet(reply["data"])
	gifts = gifts.filter(func(gift: Dictionary) -> bool: return gift.get("id") != id)
	gifts_changed.emit()
	var data: Dictionary = reply["data"]
	return {
		"item": str(data.get("item", "")), "coins": int(data.get("coins", 0)),
		"items": data["items"] if data.get("items") is Array else [], "message": str(data.get("message", "")),
	}


## Resgata a missão `key`. O código HTTP: 200 pagou, 409 incompleta ou já
## resgatada, 404 fora do ar; 0 sem conta ou sem resposta.
func claim_mission(key: String) -> int:
	if not signed_in():
		return 0
	var reply := await _call(HTTPClient.METHOD_POST, "/api/cascapp/missions/claim", {"key": key})
	if reply["code"] == 200 and reply["data"] is Dictionary:
		_take_wallet(reply["data"])
	if reply["code"] in [200, 404, 409]:
		await fetch_missions()
	return reply["code"]


## Compra um item. O código HTTP: 200 comprou, 402 sem moedas, 409 já tinha,
## 404 o servidor não vende; 0 sem conta ou sem resposta.
func buy(item: String) -> int:
	if not signed_in():
		return 0
	var reply := await _call(HTTPClient.METHOD_POST, "/api/cascapp/buy", {"item": item})
	if reply["code"] == 200 and reply["data"] is Dictionary:
		_take_wallet(reply["data"])
	return reply["code"]


## Equipa `item` no encaixe `slot`; vazio volta ao padrão. Verdadeiro se a conta
## guardou. Sem conta não equipa: o visual é da conta, e o servidor confere que
## o item foi comprado.
func equip(slot: String, item: String) -> bool:
	return await equip_all({slot: item})


## Como `equip`, vários encaixes numa gravação só (`{encaixe: item}`): o "Usar
## tudo" do kit de presente.
func equip_all(changes: Dictionary) -> bool:
	if not signed_in():
		return false
	var next := look.duplicate()
	for slot: String in changes:
		if str(changes[slot]).is_empty():
			next.erase(slot)
		else:
			next[slot] = changes[slot]
	var reply := await _call(HTTPClient.METHOD_PATCH, "/api/collections/users/records/" + user_id, {"look": next})
	if reply["code"] != 200:
		return false
	look = next
	Prefs.set_look(look)
	# O próximo aperto de mão já leva o visual novo (ver `Net.player_look`).
	Net.player_look = look
	wallet_changed.emit()
	return true


## As respostas podem chegar fora de ordem: o bônus pedido na entrada, lido
## antes de o prêmio gravar, volta depois dele com o saldo antigo. O `updated`
## do registro diz qual é a carteira mais nova, e a mais velha é ignorada.
## ponytail: precisão de milissegundo; duas gravações no mesmo milissegundo
## empatam e vale a que chegar por último.
func _take_wallet(record: Dictionary) -> void:
	var stamp := str(record.get("updated", ""))
	if stamp < _wallet_at:
		return
	_wallet_at = stamp
	coins = int(record.get("coins", 0))
	var items: Variant = record.get("owned")
	owned = items if items is Array else []
	if record.has("look"):
		look = Cosmetics.clean(record["look"])
		Prefs.set_look(look)
		# O próximo aperto de mão já leva o visual novo (ver `Net.player_look`).
		Net.player_look = look
	wallet_changed.emit()


# --- avatar ---------------------------------------------------------------------
#
# A foto já sai comprimida de `Avatar.compress`. Ela vale primeiro no aparelho
# (`AVATAR_CACHE`) e sobe para a conta quando der, como o nome: servidor fora
# deixa a troca pendente no `Prefs`, e a próxima entrada a completa.


## A foto nova do jogador, já no formato do avatar.
func set_avatar(webp: PackedByteArray) -> void:
	var file := FileAccess.open(AVATAR_CACHE, FileAccess.WRITE)
	file.store_buffer(webp)
	file.close()
	_local_texture = null
	Prefs.set_avatar_pending(true)
	avatar_changed.emit()
	push_avatar()


## A foto deste aparelho, ou `null` sem foto. Decodificada uma vez: a etiqueta
## da partida pergunta a cada lance.
func local_avatar() -> Texture2D:
	if _local_texture == null and FileAccess.file_exists(AVATAR_CACHE):
		_local_texture = Avatar.texture(FileAccess.get_file_as_bytes(AVATAR_CACHE))
	return _local_texture


## A foto de outra conta, pela miniatura. `null` enquanto ela não chegou: o
## primeiro pedido dispara o download, e [signal remote_avatar_loaded] avisa
## quando ela estiver aqui. Uma vez por arquivo enquanto o app está aberto — a
## foto trocada nasce com outro nome, e o pedido seguinte já é o dela.
func avatar_of(id: String, file: String) -> Texture2D:
	if id.is_empty() or file.is_empty():
		return null
	if not _remote.has(file):
		_remote[file] = null
		_load_remote(id, file)
	return _remote[file]


func _load_remote(id: String, file: String) -> void:
	var path := avatar_url(id, file, "128x128").trim_prefix(base_url())
	var reply := await _raw(HTTPClient.METHOD_GET, path, "", PackedByteArray())
	var picture := Avatar.texture(reply["body"]) if reply["code"] == 200 else null
	if picture == null:
		# Falhou: esquece, para a próxima pergunta tentar de novo.
		_remote.erase(file)
		return
	_remote[file] = picture
	remote_avatar_loaded.emit()


func push_avatar() -> bool:
	if not signed_in() or not FileAccess.file_exists(AVATAR_CACHE):
		return false
	var boundary := "cascapp" + _random_hex(12)
	var body := ("--%s\r\nContent-Disposition: form-data; name=\"avatar\"; filename=\"avatar.webp\"\r\nContent-Type: image/webp\r\n\r\n" % boundary).to_utf8_buffer()
	body.append_array(FileAccess.get_file_as_bytes(AVATAR_CACHE))
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	var reply := await _raw(
		HTTPClient.METHOD_PATCH, "/api/collections/users/records/" + user_id,
		"multipart/form-data; boundary=" + boundary, body
	)
	if reply["code"] != 200:
		return false
	var data: Variant = JSON.parse_string((reply["body"] as PackedByteArray).get_string_from_utf8())
	if data is Dictionary:
		avatar_file = str(data.get("avatar", ""))
	Prefs.set_avatar_pending(false)
	return true


## O endereço público da foto de uma conta. `thumb` é uma das miniaturas da
## coleção (`128x128`); vazio, a foto inteira.
static func avatar_url(id: String, file: String, thumb := "") -> String:
	var url := "%s/api/files/users/%s/%s" % [base_url(), id, file]
	return url + ("?thumb=" + thumb if not thumb.is_empty() else "")


func _fetch_own_avatar() -> void:
	var reply := await _raw(HTTPClient.METHOD_GET, avatar_url(user_id, avatar_file).trim_prefix(base_url()), "", PackedByteArray())
	if reply["code"] != 200 or Avatar.decode(reply["body"]) == null:
		return
	var file := FileAccess.open(AVATAR_CACHE, FileAccess.WRITE)
	file.store_buffer(reply["body"])
	file.close()
	_local_texture = null
	avatar_changed.emit()


# --- conta protegida por e-mail ---------------------------------------------------
#
# Rotas de `pocketbase/pb_hooks/conta.pb.js`. O servidor grava o e-mail
# confirmado como o da conta, mas o app continua entrando com a credencial do
# aparelho (o `device_login` de lá), e o e-mail só serve para trazer a conta de
# volta a um aparelho novo.


## Pede o código para `email`, com `purpose` "protect" ou "recover". O código
## HTTP: 200 saiu, 400 e-mail inválido, 429 códigos demais, 502 o e-mail não
## saiu, 0 sem conta ou sem servidor.
func email_start(email: String, purpose: String) -> int:
	if not signed_in():
		return 0
	var reply := await _call(HTTPClient.METHOD_POST, "/api/cascapp/email/start", {"email": email.strip_edges(), "purpose": purpose})
	return reply["code"]


## Confirma a proteção com o código que chegou. `{"code": HTTP, "reason"}`:
## 200 protegida, 400 código inválido (`reason` "wrong", "expired", "locked" ou
## "missing"), 409 o e-mail já protege outra conta, 0 sem conta ou sem servidor.
func email_protect(code: String) -> Dictionary:
	if not signed_in():
		return {"code": 0, "reason": ""}
	var reply := await _call(HTTPClient.METHOD_POST, "/api/cascapp/email/protect", {"code": code})
	var data: Variant = reply["data"]
	if reply["code"] == 200 and data is Dictionary:
		contact_email = str(data.get("contact_email", ""))
	return {"code": reply["code"], "reason": str(data.get("reason", "")) if data is Dictionary else ""}


## Volta para a conta protegida por `email`, com o código que chegou nele. O
## servidor apaga a conta deste aparelho e passa a credencial dele para a conta
## antiga; aqui o app entra de novo e fica com o nome e a foto de lá.
## `{"code": HTTP, "reason"}`: 200 voltou, 400 código inválido (`reason` como
## em [method email_protect], ou "same" quando a conta já é esta), 403
## credencial recusada, 0 sem conta ou sem servidor.
func email_recover(email: String, code: String) -> Dictionary:
	if not signed_in():
		return {"code": 0, "reason": ""}
	var reply := await _call(HTTPClient.METHOD_POST, "/api/cascapp/email/recover", {
		"email": email.strip_edges(), "code": code, "password": _credentials()["password"],
	})
	var data: Variant = reply["data"]
	if reply["code"] == 200:
		await _adopt()
	return {"code": reply["code"], "reason": str(data.get("reason", "")) if data is Dictionary else ""}


## O aparelho deixa o que era da conta vazia e fica com o da conta antiga. Sem
## isto, a entrada empurraria o nome e a foto deste aparelho por cima dos de lá.
func _adopt() -> void:
	Prefs.set_player_name("")
	Prefs.set_avatar_pending(false)
	if FileAccess.file_exists(AVATAR_CACHE):
		DirAccess.remove_absolute(AVATAR_CACHE)
	_local_texture = null
	sign_out()
	if await sign_in() and not _name.is_empty():
		Prefs.set_player_name(_name)
	# Sem foto na conta antiga, quem mostra a deste aparelho passa a mostrar
	# nenhuma; com foto, ela chega depois pelo mesmo sinal.
	avatar_changed.emit()


## "lucas@gmail.com" → "l***@gmail.com", como em `pocketbase/pb_hooks/conta.js`.
static func masked_email(email: String) -> String:
	var at := email.find("@")
	return "" if at < 1 else email[0] + "***" + email.substr(at)


## Esquece a sessão (não a conta): os testes, e a volta para a conta antiga.
func sign_out() -> void:
	# Antes do token: quem escuta `signed_in_changed` já lê a conta vazia.
	contact_email = ""
	_set_token("", "")
	coins = -1
	owned = []
	missions = []
	events = []
	missions_notice = []
	gifts = []
	gifts_sent_today = []
	_daily_day = ""
	_wallet_at = ""


## `{"email", "password"}` deste aparelho, sempre os mesmos.
##
## Sem id de aparelho (plataforma que não informa), um sorteado uma vez e
## guardado no `Prefs` faz o papel — e aí a reinstalação volta a criar outra.
func _credentials() -> Dictionary:
	var seed := device_seed if not device_seed.is_empty() else OS.get_unique_id()
	if seed.is_empty():
		seed = Prefs.account_seed()
		if seed.is_empty():
			seed = _random_hex(16)
			Prefs.set_account_seed(seed)
	return {
		"email": "%s@%s" % [("cascapp:email:" + seed).sha256_text().left(32), EMAIL_DOMAIN],
		"password": ("cascapp:password:" + seed).sha256_text(),
	}


func _create(credentials: Dictionary) -> bool:
	var body := {
		"email": credentials["email"],
		"password": credentials["password"],
		"passwordConfirm": credentials["password"],
	}
	if Prefs.has_name():
		body["name"] = Prefs.player_name()
	var reply := await _call(HTTPClient.METHOD_POST, "/api/collections/users/records", body)
	return reply["code"] == 200


## O código HTTP da tentativa: 200 entrou, 400 credencial recusada, 0 sem
## resposta (rede, servidor fora do ar).
func _authenticate(credentials: Dictionary) -> int:
	var reply := await _call(
		HTTPClient.METHOD_POST, "/api/collections/users/auth-with-password",
		{"identity": credentials["email"], "password": credentials["password"]}
	)
	var data: Variant = reply["data"]
	if reply["code"] != 200:
		return reply["code"]
	if not data is Dictionary or not data.has("token"):
		return 0
	_name = str(data["record"].get("name", ""))
	avatar_file = str(data["record"].get("avatar", ""))
	elo = int(data["record"].get("elo_chess", 0))
	friend_code = str(data["record"].get("friend_code", ""))
	contact_email = str(data["record"].get("contact_email", ""))
	_set_token(str(data["token"]), str(data["record"]["id"]))
	_take_wallet(data["record"])
	return 200


func _set_token(value: String, id: String) -> void:
	var before := signed_in()
	token = value
	user_id = id
	if signed_in() != before:
		signed_in_changed.emit(signed_in())


## `{"code": int, "data": Variant}`; `code` 0 quando nem resposta houve.
func _call(method: int, path: String, body: Dictionary) -> Dictionary:
	var reply := await _raw(method, path, "application/json", JSON.stringify(body).to_utf8_buffer())
	var text := (reply["body"] as PackedByteArray).get_string_from_utf8()
	# 204 (apagar) vem sem corpo, e o parser reclamaria do vazio.
	return {"code": reply["code"], "data": JSON.parse_string(text) if not text.is_empty() else null}


## `{"code": int, "body": PackedByteArray}`, para corpo que não é JSON (a foto).
func _raw(method: int, path: String, content_type: String, body: PackedByteArray) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SECONDS
	add_child(http)
	var headers := PackedStringArray()
	if not content_type.is_empty():
		headers.append("Content-Type: " + content_type)
	if signed_in():
		headers.append("Authorization: " + token)
	var started := http.request_raw(base_url() + path, headers, method, body)
	var reply := {"code": 0, "body": PackedByteArray()}
	if started == OK:
		var result: Array = await http.request_completed
		if result[0] == HTTPRequest.RESULT_SUCCESS:
			reply["code"] = result[1]
			reply["body"] = result[3]
	http.queue_free()
	return reply


static func _random_hex(bytes: int) -> String:
	return Crypto.new().generate_random_bytes(bytes).hex_encode()
