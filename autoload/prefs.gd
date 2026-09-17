class_name Prefs
extends RefCounted

## O que o jogador escolheu sobre si mesmo, guardado no aparelho.
##
## Hoje é só o nome, e ainda assim vale um arquivo: ele atravessa partidas e
## execuções, e é a primeira coisa que um dia viaja no aperto de mão para o
## outro lado saber com quem está jogando — hoje o oponente é "Oponente".
##
## `user://`, e não `res://`: o segundo é o pacote do app, somente leitura no
## Android. `ConfigFile` e não JSON porque o formato é chave-valor, o Godot já
## sabe ler e escrever, e um arquivo de preferências que um humano consegue
## abrir e corrigir vale mais que um byte a menos.
##
## Estático e não autoload. Um autoload é um nó vivo na árvore a partida
## inteira; isto é um arquivo lido uma vez e escrito quando alguém muda de
## ideia. O cache em `static var` dá o mesmo acesso global sem o nó.

const PATH := "user://prefs.cfg"
const SECTION := "player"
const NAME_KEY := "name"
## Cabe num cartão de jogador sem reticências, e é mais que qualquer apelido
## real. O limite existe para o layout, não para a moral.
const NAME_LIMIT := 18

## Nome de quem ainda não escolheu um. Não é um vazio disfarçado: a tela de
## partida precisa escrever alguma coisa no cartão de baixo, e "Guidon" é o que
## descreve corretamente quem está segurando o aparelho.
const DEFAULT_NAME := "Guidon"

const SOUND_KEY := "sound"
const HAPTICS_KEY := "haptics"
const WELCOMED_KEY := "welcomed"
const SEVENS_KEY := "uno_sevens"
const FAVORITES_KEY := "favorites"

static var _config: ConfigFile = null


static func player_name() -> String:
	var stored := str(_file().get_value(SECTION, NAME_KEY, ""))
	return stored if not stored.is_empty() else DEFAULT_NAME


## Verdadeiro quando o jogador escolheu um nome. A tela de ajustes usa isto para
## não mostrar "Você" dentro do campo como se fosse texto digitado — um valor
## que parece escolhido e não foi é a receita para ninguém escolher.
static func has_name() -> bool:
	return not str(_file().get_value(SECTION, NAME_KEY, "")).is_empty()


## Guardar nome vazio é apagar o nome, e não gravar espaço em branco: quem
## limpou o campo quer voltar ao padrão.
static func set_player_name(value: String) -> void:
	var clean := value.strip_edges().substr(0, NAME_LIMIT)
	if clean.is_empty():
		# Só apaga o que existe: apagar chave de seção ausente é erro no
		# `ConfigFile`, e o caso normal — limpar o campo sem nunca ter salvado
		# nada — cairia justamente nele.
		if _file().has_section_key(SECTION, NAME_KEY):
			_file().erase_section_key(SECTION, NAME_KEY)
	else:
		_file().set_value(SECTION, NAME_KEY, clean)
	_file().save(PATH)


## Som e vibração, os dois **ligados** por padrão.
##
## Ligado e não desligado porque um jogo de tabuleiro sem som é o que o app era
## até aqui, e quem nunca abre os ajustes é justamente quem não vai descobrir que
## existe o que ligar. Quem se incomoda desliga uma vez e fica desligado.
##
## Dois interruptores e não um: no ônibus se quer a vibração sem o som, e numa
## mesa de quatro se quer o som sem o aparelho tremendo na mão de ninguém.
static func sound_on() -> bool:
	return bool(_file().get_value(SECTION, SOUND_KEY, true))


static func haptics_on() -> bool:
	return bool(_file().get_value(SECTION, HAPTICS_KEY, true))


static func set_sound(value: bool) -> void:
	_file().set_value(SECTION, SOUND_KEY, value)
	_file().save(PATH)


static func set_haptics(value: bool) -> void:
	_file().set_value(SECTION, HAPTICS_KEY, value)
	_file().save(PATH)


## A regra da casa do 0 e do 7, no Uno. **Ligada** por padrão.
##
## Guardada no disco, e não só no `Game` como o formato de Metrópole: regra de
## casa é de quem joga, não da sessão. Quem joga Uno com 0 e 7 joga sempre, e
## reperguntar a cada partida é perguntar algo cuja resposta não muda.
##
## Ligada por padrão pelo mesmo motivo do som: quem instala o jogo para jogar com
## ela é quem menos vai procurar onde ligá-la, e quem não a quer desliga uma vez.
## Vale notar que a resposta padrão aqui é diferente da de Metrópole, onde "até a
## falência" é o jogo como ele é — o 0 e o 7 não são o Uno de caixa, e mesmo assim
## são o Uno que se joga.
static func sevens_on() -> bool:
	return bool(_file().get_value(SECTION, SEVENS_KEY, true))


static func set_sevens(value: bool) -> void:
	_file().set_value(SECTION, SEVENS_KEY, value)
	_file().save(PATH)


## Os jogos que o jogador marcou com a estrela, como `String` e não `StringName`.
##
## `String` porque é o que o `ConfigFile` devolve de um `PackedStringArray` lido
## do disco, e converter na volta só serviria para converter de novo na ida. Quem
## compara com um id do catálogo envolve em `String()` — é o que `Game` faz.
##
## No disco e não no `Game`: favorito é do jogador, não da sessão. É a mesma
## razão da regra do 0 e do 7 no Uno, e a diferença com o resto do `Game` — modo,
## ritmo, tamanho de mesa — é que aqueles são decisões de **uma** partida.
static func favorites() -> PackedStringArray:
	var stored = _file().get_value(SECTION, FAVORITES_KEY, PackedStringArray())
	return PackedStringArray(stored)


static func is_favorite(id: StringName) -> bool:
	return favorites().has(String(id))


## Marca ou desmarca, e devolve como ficou.
##
## Devolve o estado novo porque quem chama acabou de pedir a troca e vai
## redesenhar a estrela com ela: ler o disco de novo logo depois de escrever é
## perguntar uma coisa que já se sabe.
static func toggle_favorite(id: StringName) -> bool:
	var list := favorites()
	var key := String(id)
	var at := list.find(key)
	var now := at < 0
	if now:
		list.append(key)
	else:
		list.remove_at(at)
	_file().set_value(SECTION, FAVORITES_KEY, list)
	_file().save(PATH)
	return now


## Esquece todos os favoritos. Como `forget_welcome()`, não há caminho no app que
## chegue aqui: quem chama é o teste que precisa da lista na ordem do catálogo e a
## folha de prints que fotografa a tela recém-instalada.
static func forget_favorites() -> void:
	if _file().has_section_key(SECTION, FAVORITES_KEY):
		_file().erase_section_key(SECTION, FAVORITES_KEY)
		_file().save(PATH)


## O jogador já viu a tela de boas-vindas.
##
## Uma chave própria, e não `has_name()`. Os dois quase sempre concordam, e o
## caso em que discordam é o que importa: quem abriu, leu, decidiu ficar com o
## nome padrão e seguiu para o jogo. Guardado por `has_name()`, ele receberia a
## mesma boas-vindas em toda abertura do app — e uma tela de boas-vindas que
## reaparece deixa de ser boas-vindas e vira cobrança.
static func welcomed() -> bool:
	return bool(_file().get_value(SECTION, WELCOMED_KEY, false))


static func set_welcomed() -> void:
	_file().set_value(SECTION, WELCOMED_KEY, true)
	_file().save(PATH)


## Desfaz a marca. Não há caminho no app que chegue aqui — quem chama é o teste
## que precisa da primeira abertura e a folha de prints que precisa fotografá-la.
##
## Existe porque as duas precisavam **apagar** a chave, e não gravar `false`:
## `pending()` pergunta se a marca existe, e um `false` gravado responderia a
## mesma coisa por um caminho diferente. As duas escreviam a mesma dança com
## `ConfigFile` à mão, e a segunda cópia é onde uma delas erra a seção.
static func forget_welcome() -> void:
	if _file().has_section_key(SECTION, WELCOMED_KEY):
		_file().erase_section_key(SECTION, WELCOMED_KEY)
		_file().save(PATH)


## Quando começou a partida que está em curso, e de que sala ela é.
##
## Uma sala só, a última: isto existe para a reconexão, e quem reconecta volta
## para a partida de onde acabou de cair. Um histórico de salas responderia uma
## pergunta que ninguém faz.
const MATCH_SECTION := "match"
const MATCH_CODE_KEY := "code"
const MATCH_START_KEY := "started_at"


## O instante em que a partida da sala `code` começou, gravando `now` se for a
## primeira vez que se pergunta por ela.
##
## É o que faz o relógio da faixa sobreviver a uma queda. Sem isto, quem fecha o
## app e volta pela mesma sala reencontra a partida no lance certo e o relógio em
## zero — e um relógio que discorda dos outros aparelhos é pior que relógio
## nenhum, porque parece que a partida recomeçou.
##
## Em disco, e não em memória: a queda que importa é a do processo. Um jogador
## que só perdeu o Wi-Fi nunca chega aqui.
static func match_start(code: String, now: int) -> int:
	if str(_file().get_value(MATCH_SECTION, MATCH_CODE_KEY, "")) == code:
		var stored := int(_file().get_value(MATCH_SECTION, MATCH_START_KEY, 0))
		if stored > 0:
			return stored
	return restart_match(code, now)


## Começa a contar de novo, mesmo que a sala seja a mesma. É a revanche: o código
## não muda, e a partida é outra.
static func restart_match(code: String, now: int) -> int:
	_file().set_value(MATCH_SECTION, MATCH_CODE_KEY, code)
	_file().set_value(MATCH_SECTION, MATCH_START_KEY, now)
	_file().save(PATH)
	return now


## A cadeira da última partida em rede: sala, jogo e a chave do assento.
##
## Seção própria, e não os campos do relógio acima. Os dois respondem perguntas
## diferentes em momentos diferentes — o relógio pergunta "esta sala é a mesma de
## antes?" ao abrir **qualquer** partida, e escrever o código aqui antes daquela
## pergunta faria uma partida nova herdar o começo da anterior.
##
## A chave é o que devolve **o mesmo** assento. Sem ela o relay senta quem volta no
## primeiro livre, e numa mesa com duas pessoas fora isso troca as duas de lugar —
## cada uma jogando com as cartas da outra.
const REJOIN_SECTION := "rejoin"
## O teto de vida de uma sala no relay (`roomMaxMs`). Depois disso ela não existe
## mais, e oferecer a volta seria oferecer um "partida não encontrada".
const REJOIN_WINDOW := 4 * 60 * 60


static func remember_rejoin(code: String, game: StringName, key: String, now: int) -> void:
	_file().set_value(REJOIN_SECTION, "code", code)
	_file().set_value(REJOIN_SECTION, "game", String(game))
	_file().set_value(REJOIN_SECTION, "key", key)
	_file().set_value(REJOIN_SECTION, "at", now)
	_file().save(PATH)


## A partida para onde dá para voltar, ou vazio. `{code, game, key, at}`.
static func pending_rejoin(now: int) -> Dictionary:
	var code := str(_file().get_value(REJOIN_SECTION, "code", ""))
	var at := int(_file().get_value(REJOIN_SECTION, "at", 0))
	if code.is_empty() or now - at > REJOIN_WINDOW:
		return {}
	return {
		"code": code,
		"game": StringName(str(_file().get_value(REJOIN_SECTION, "game", ""))),
		"key": str(_file().get_value(REJOIN_SECTION, "key", "")),
		"at": at,
	}


## A chave do assento que este aparelho ocupava na sala `code`, ou vazio.
##
## Por código, e não "a última chave": quem digita o código de **outra** sala não
## pode mandar a chave desta — o servidor não a acharia e o sentaria no primeiro
## livre de qualquer jeito, mas é um segredo indo para onde não precisa.
static func rejoin_key(code: String) -> String:
	if str(_file().get_value(REJOIN_SECTION, "code", "")) != code.to_upper():
		return ""
	return str(_file().get_value(REJOIN_SECTION, "key", ""))


static func forget_rejoin() -> void:
	if not _file().has_section(REJOIN_SECTION):
		return
	_file().erase_section(REJOIN_SECTION)
	_file().save(PATH)


## Arquivo carregado uma vez por execução. Ausente é o caso normal na primeira
## abertura — um `ConfigFile` vazio responde a tudo com o padrão, então não há
## nada a tratar.
static func _file() -> ConfigFile:
	if _config == null:
		_config = ConfigFile.new()
		_config.load(PATH)
	return _config


## Só para os testes: obriga a próxima leitura a voltar ao disco.
static func forget() -> void:
	_config = null
