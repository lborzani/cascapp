extends Control

## A aba Loja: a `ShopPanel` inteira, com as abas na base.
##
## Era um atalho da grade da aba Você e a pílula de moedas do topo, que abriam a
## loja por cima da tela. Um lugar que se visita toda vez que entra moeda merece
## estar na base, à vista, como os outros.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const JOIN_SCENE := "res://scenes/join.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"

var _leaving := false


func _ready() -> void:
	# Window.theme não desce para os Controls; o tema entra pela raiz da cena.
	theme = AppTheme.shared()
	%Tabs.current = AppTabs.SHOP
	if not Net.relay_available():
		%Tabs.disabled = [AppTabs.ONLINE] as Array[StringName]
	%Tabs.picked.connect(_go_tab)


func _go_tab(route: StringName) -> void:
	Sound.play(Sound.Cue.TAP)
	match route:
		AppTabs.GAMES:
			_go(MENU_SCENE)
		AppTabs.ONLINE:
			_go(JOIN_SCENE)
		AppTabs.YOU:
			_go(SETTINGS_SCENE)


func _go(path: String) -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(path)


## Com a lista de amigos aberta, o gesto fecha só ela; senão, volta à inicial.
func go_back() -> void:
	if %Shop.picking():
		%Shop.close()
		return
	_go(MENU_SCENE)
