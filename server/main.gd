extends Node

## O servidor de Bomberman, headless.
##
##   godot --headless --path . res://server/main.tscn -- --port 27016
##
## É o mesmo projeto do cliente, sem tela. Não há um segundo código de regras aqui:
## [BomberRoom] chama [BomberRules], o mesmo arquivo que o celular chama. É por isso
## que `core/` não conhece `ui/` nem `scenes/` — se conhecesse, este arquivo
## precisaria de uma tela pra rodar uma partida que ninguém vê.
##
## O ciclo de vida das salas mora em [BomberNet]; este arquivo abre a porta,
## imprime o que acontece, e sai da frente. Os outros cinco jogos do app **não**
## passam por aqui: eles falam pelo relay, que é outro processo.

const REPORT_SECONDS := 30.0

var _since_report := 0.0


func _ready() -> void:
	var port := _port_from_command_line()
	var problem := BomberNet.start_server(port)
	if problem != OK:
		printerr("não foi possível abrir a porta %d: %s" % [port, error_string(problem)])
		get_tree().quit(1)
		return
	print(
		"Bomberman — servidor ouvindo em %d, %d Hz, protocolo v%d"
		% [port, BomberRules.TICK_HZ, BomberProtocol.VERSION]
	)


const PORT_ENV := "BOMBER_PORT"


## A porta, do argumento ou do ambiente. `--port N` depois do `--` que separa os
## argumentos do jogo dos do Godot — sem isso, subir dois servidores na mesma
## máquina (o que o teste de rede faz) exigiria editar uma constante entre um e
## outro. A variável de ambiente existe pro container.
func _port_from_command_line() -> int:
	var args := OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--port" and index + 1 < args.size():
			return int(args[index + 1])
	var from_env := OS.get_environment(PORT_ENV)
	if from_env != "" and from_env.is_valid_int():
		return int(from_env)
	return BomberProtocol.PORT


func _process(delta: float) -> void:
	_since_report += delta
	if _since_report < REPORT_SECONDS:
		return
	_since_report = 0.0
	print("salas: %d" % BomberNet._rooms.size())
