class_name Ruleset
extends RefCounted

## Interface implemented by ChessRules and CheckersRules. The match scene and
## the board view only ever talk to this, so adding a third game means adding a
## file here and one entry in `game_state.gd`.

enum Outcome { ONGOING, WHITE_WINS, BLACK_WINS, DRAW }


func id() -> StringName:
	return &""


func display_name() -> String:
	return ""


func initial_state() -> MatchState:
	return MatchState.new()


func generate_moves(_state: MatchState) -> Array[Move]:
	return []


## Mutates `state` in place. The caller is responsible for only passing moves
## produced by `generate_moves`.
func apply_move(_state: MatchState, _move: Move) -> void:
	pass


func outcome(_state: MatchState) -> Outcome:
	return Outcome.ONGOING


## Quantos jogadores se revezam. Dois é o caso de três dos cinco jogos, e é o
## padrão por isso.
##
## Não é o mesmo que "de quantos é a mesa" do catálogo: aquilo é o que o menu
## ofereceu, isto é o que a **regra** faz. Em Metrópole os dois coincidem porque a
## mesa é escolhida; no Ludo são quatro cantos, escolha nenhuma.
func players() -> int:
	return 2


## Rodadas **completas** — quantas voltas a mesa já deu. A rodada em curso não
## conta: a pergunta é quanto de partida já passou, e a que está acontecendo
## ainda não passou.
##
## Mora aqui e não na tela porque uma volta na mesa é conceito de jogo. A conta
## padrão serve a quem alterna estritamente, que é xadrez, damas, batalha naval e
## — de perto o bastante — o Ludo. Metrópole não alterna: um par de dados iguais
## devolve a vez ao mesmo jogador, então ela conta a própria rodada e sobrescreve
## isto.
func rounds_played(state: MatchState) -> int:
	return state.ply / maxi(1, players())


## Dark squares only, for checkers. Chess uses every square.
func square_is_playable(_sq: int) -> bool:
	return true


## Quanto a posição vale para as **brancas**, em centésimos de peão. Positivo é
## bom para as brancas, negativo para as pretas, zero é equilíbrio.
##
## Mora aqui, junto das regras, porque o que uma peça vale é parte de saber jogar
## o jogo: uma dama de damas voa e vale três pedras, um bispo de xadrez vale um
## pouco mais que um cavalo. O `Bot` procura fundo sem saber nada disso — ele só
## pergunta quanto vale o que encontrou, e por isso um terceiro jogo entra sem
## tocar na busca.
##
## Sempre do ponto de vista das brancas, e nunca do lado da vez: uma pontuação
## que troca de sinal sozinha a cada lance é a fonte clássica de bug de busca.
func evaluate(_state: MatchState) -> float:
	return 0.0


## Quanto material este lance ganha de imediato, na mesma escala de `evaluate`.
##
## Existe para a busca de sossego poder **desistir cedo** de uma captura que não
## salva a posição nem no melhor caso: comer um peão não recupera uma dama de
## desvantagem, e descer a árvore de recapturas para confirmar isso é onde ia a
## maior parte do orçamento de tempo do bot numa posição cheia.
##
## Zero é a resposta honesta de quem não sabe medir — e desliga a poda, que é o
## comportamento seguro. O `Bot` continua sem conhecer jogo nenhum: ele pergunta
## quanto vale, como já pergunta quanto vale a posição.
func capture_gain(_state: MatchState, _move: Move) -> float:
	return 0.0


## Extra line under the board ("check!", "capture obligatory", ...).
func status_hint(_state: MatchState) -> String:
	return ""


## O lance escrito, para o histórico. `state` é a posição **antes** do lance —
## é dela que saem a desambiguação e a peça que se move, e é ela que a regra
## clona internamente para descobrir se o lance dá xeque.
##
## Mora aqui e não na tela porque notação é regra de jogo: xadrez desambigua
## por peça, damas encadeia saltos. A tela só empilha strings.
func notation(_state: MatchState, _move: Move) -> String:
	return ""


## Called when a move ends on the promotion rank and more than one piece can be
## chosen. Empty array means "no choice to make".
func promotion_options(_state: MatchState, _move_path: PackedInt32Array) -> Array[int]:
	return []


func outcome_text(result: Outcome) -> String:
	match result:
		Outcome.WHITE_WINS:
			return "Brancas venceram"
		Outcome.BLACK_WINS:
			return "Pretas venceram"
		Outcome.DRAW:
			return "Empate"
		_:
			return ""
