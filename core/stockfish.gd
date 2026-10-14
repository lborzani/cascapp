class_name Stockfish
extends RefCounted

## O Stockfish num processo à parte, falando UCI pela entrada e saída padrão.
##
## **Síncrono de propósito.** Cada chamada escreve e espera a resposta, então
## quem usa já roda numa `Thread` — o bot e o review têm a sua. Uma conversa
## assíncrona aqui seria uma segunda fila de mensagens para quem já não está na
## thread principal.
##
## O mesmo código serve ao Android e ao desktop: `OS.execute_with_pipe` existe
## nos dois. No Android o binário é a `libstockfish.so` que viaja no AAR do
## plugin — o sistema só deixa executar arquivo do diretório de bibliotecas
## nativas do app (W^X desde o Android 10), e o plugin existe só para dizer onde
## esse diretório fica. No desktop é o `stockfish` do PATH, ou `$STOCKFISH`.
##
## Licença: Stockfish é GPLv3. Ele vai como executável separado, mas a
## distribuição ainda pede o aviso e o link para o código-fonte.

const PLUGIN := "GodotStockfish"

var _stdio: FileAccess = null
var _pid := -1


static func binary() -> String:
	if Engine.has_singleton(PLUGIN):
		return Engine.get_singleton(PLUGIN).binaryPath()
	return OS.get_environment("STOCKFISH") if OS.has_environment("STOCKFISH") else "stockfish"


## Sobe o processo e espera o `uciok`. Falso quando não há motor — o binário não
## existe, não executa nesta arquitetura, ou morre na largada — e aí quem chamou
## usa o `Bot` antigo.
func start(path := binary()) -> bool:
	var proc := OS.execute_with_pipe(path, [])
	if proc.is_empty():
		return false
	_stdio = proc["stdio"]
	_pid = int(proc["pid"])
	_send("uci")
	if not _wait_for("uciok"):
		quit()
		return false
	_send("setoption name UCI_ShowWDL value true")
	return ready()


func running() -> bool:
	return _stdio != null


## `elo` 0 é força total (o review); qualquer outro limita (o bot).
func set_strength(elo: int) -> void:
	if elo <= 0:
		_send("setoption name UCI_LimitStrength value false")
		return
	_send("setoption name UCI_LimitStrength value true")
	_send("setoption name UCI_Elo value %d" % elo)


func ready() -> bool:
	_send("isready")
	return _wait_for("readyok")


## Procura `movetime_ms` na posição e devolve o que o motor viu, sempre do ponto
## de vista de quem tem a vez:
##
##   {"best": "e2e4", "cp": 31, "mate": 0, "wdl": [w, d, l]}
##
## `mate` diferente de zero substitui `cp` (positivo: quem joga dá mate). `best`
## é "(none)" sem lance legal. Dicionário vazio quando o motor morreu.
func search(fen: String, movetime_ms: int) -> Dictionary:
	_send("position fen " + fen)
	_send("go movetime %d" % movetime_ms)
	var result := {"cp": 0, "mate": 0, "wdl": [0, 1000, 0]}
	while running():
		var line := _read()
		if line.begins_with("bestmove"):
			result["best"] = line.split(" ")[1]
			return result
		if line.begins_with("info") and line.contains(" score "):
			_parse_info(line.split(" "), result)
	return {}


func quit() -> void:
	if _stdio == null:
		return
	_send("quit")
	_stdio.close()
	_stdio = null
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1


func _parse_info(words: PackedStringArray, result: Dictionary) -> void:
	for i in words.size() - 1:
		match words[i]:
			"cp":
				result["cp"] = int(words[i + 1])
				result["mate"] = 0
			"mate":
				result["mate"] = int(words[i + 1])
			"wdl":
				result["wdl"] = [int(words[i + 1]), int(words[i + 2]), int(words[i + 3])]


func _send(command: String) -> void:
	if _stdio != null:
		_stdio.store_line(command)
		_stdio.flush()


## Uma linha, ou "" com o motor marcado como morto quando o cano fechou. Sem
## isso, um processo que caiu deixaria a thread lendo vazio para sempre.
func _read() -> String:
	var line := _stdio.get_line()
	if line.is_empty() and (_stdio.get_error() != OK or not OS.is_process_running(_pid)):
		_stdio.close()
		_stdio = null
	return line.strip_edges()


func _wait_for(token: String) -> bool:
	while running():
		if _read() == token:
			return true
	return false
