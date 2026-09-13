class_name Orientation
extends RefCounted

## Gira o aparelho para o jogo que precisa de largura, e desgira ao sair.
##
## O app inteiro é retrato: `window/handheld/orientation=1` no projeto, e uma
## base de 432x768 que todas as telas assumem. Um jogo só discorda — o tabuleiro
## do Monopoly é um anel quadrado cercado de painéis de texto, e em retrato ele
## fica com metade da largura da tela enquanto sobra faixa preta em cima e
## embaixo.
##
## ## Girar são duas coisas, não uma
##
## Trocar só a orientação **estraga a escala**. Com `stretch/aspect="expand"` o
## fator é `min(largura/432, altura/768)`; num aparelho 2400x1080 deitado isso dá
## 1,4 em vez dos ~2,5 de retrato, e a base vira ~1714 unidades de largura. Como
## fonte, margem e raio estão todos escritos para uma tela de 432, o resultado é
## a UI inteira encolhida no meio de um oceano de espaço.
##
## Então a base também gira: 768x432. Aí o fator volta a ~2,5, as fontes voltam
## ao tamanho de sempre, e a tela deitada tem a largura que o tabuleiro pediu.
##
## ## Estático, e não autoload
##
## Não guarda nada além do que o `DisplayServer` já sabe — `reset()` devolve os
## valores do projeto, que são constantes. Um autoload aqui seria um nó vivo a
## sessão inteira para duas chamadas de função. Mesmo motivo de [prefs.gd].

## O que o projeto declara, e para onde `reset()` volta. Ler de
## `ProjectSettings` em vez de repetir os números evita que trocar a base do app
## um dia deixe este arquivo mentindo.
static func _portrait_size() -> Vector2i:
	return Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 432)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 768))
	)


## A base deitada é a de pé com os eixos trocados. Não é um segundo conjunto de
## números a manter: é o mesmo, lido ao contrário.
static func _landscape_size() -> Vector2i:
	var portrait := _portrait_size()
	return Vector2i(portrait.y, portrait.x)


## Põe o aparelho deitado. `SCREEN_SENSOR_LANDSCAPE` e não `SCREEN_LANDSCAPE`:
## quem joga deitado vira o celular para o lado que der, e travar num só faz o
## jogo aparecer de cabeça para baixo na metade das vezes.
static func to_landscape(tree: SceneTree) -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	_set_base(tree, _landscape_size())


## Volta ao retrato do projeto. Chamado de `Game.reset_to_menu()`, que é por onde
## toda saída de partida passa — pôr isto em cada `_leave()` seria uma tela nova
## esquecendo um dia, e o menu abrindo deitado sem ninguém entender por quê.
static func reset(tree: SceneTree) -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	_set_base(tree, _portrait_size())


static func _set_base(tree: SceneTree, size: Vector2i) -> void:
	if tree == null:
		return
	var root := tree.root
	if root == null or root.content_scale_size == size:
		return
	root.content_scale_size = size
