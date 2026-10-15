# Jogos de Rolê — multiplayer por código, sem cadastro

Coleção de jogos para celular, hoje com **xadrez**, **damas**, **batalha naval**,
**Ludo**, **Metrópole**, **Uno**, **Bomberman** e **sinuca**. Dá para jogar
contra um bot, com alguém no mesmo aparelho, ou pela internet: um **abre uma
sala** e o outro entra digitando o **código de 6 caracteres** — de qualquer
lugar, cada um na sua rede, um deles em dados móveis se quiser. Também dá para
entrar apontando a câmera para o **QR Code** ou **encostando os celulares
(NFC)**.

Cada jogo declara em `Game.GAMES` como pode ser jogado, e nenhuma tela precisa
saber o nome de jogo nenhum para desenhar o menu: xadrez e damas aceitam os três
modos; batalha naval e Uno só a sala e o solo, porque mão escondida num aparelho
só exigiria uma cortina de "passe o celular" a cada jogada; Ludo e Metrópole
sentam até quatro e seis.

> O nome vem de a coleção ser o ponto, e não os jogos que existem hoje: Dominó,
> Truco e Campo Minado estão no plano, e um título que precisa ser
> reescrito a cada jogo novo é um título que não descreve o app. O identificador
> do projeto (`chess-checkers`) e o pacote Android
> (`org.chessandcheckers.game`) ficaram como estavam de propósito — mudar o
> primeiro move os dados salvos no aparelho, e mudar o segundo faz o Android
> tratar o app como outro aplicativo, com desinstalação no meio.

Nenhuma tela liga rádio nenhum por conta própria: o app usa a rede que já
estiver ligada, e a câmera e o NFC só acordam quando você toca no botão.

Nada de conta nem login. O único servidor envolvido é um relay que emparelha
dois sockets e repassa bytes — ele não sabe jogar xadrez, não guarda partida e
não tem usuário.

Feito em **Godot 4.7 / GDScript**.

---

## O que está implementado

### Regras

**Xadrez** — regras completas: movimentação de todas as peças, roque dos dois
lados (com verificação de casas atacadas), *en passant*, promoção com escolha de
peça, xeque, xeque-mate, afogamento, regra dos 50 lances e os empates por
material insuficiente mais comuns.

Para rocar, toque no rei e depois na casa de destino **ou na própria torre** —
tocar na torre é como a maioria das pessoas faz e como os sites grandes aceitam.
Sem esse atalho o toque cai numa casa sem lance associado e o roque parece
quebrado mesmo estando gerado corretamente.

**Damas** — 8x8, 12 pedras por lado, pedra captura para frente e para trás, dama
"voadora" (anda e captura à distância) e regra turca (a peça capturada só sai do
tabuleiro no fim da sequência e não pode ser saltada duas vezes). Promoção só
acontece quando a pedra *termina* o lance na última linha.

**Captura é opcional**, diferente das regras de torneio. A obrigatoriedade (e a
lei da maioria, que força a maior sequência) fazia o tabuleiro parecer quebrado:
tocar numa pedra que podia mover mas não era a da captura obrigatória não fazia
nada, sem como a interface explicar o motivo. Uma sequência iniciada ainda
precisa ser terminada — você escolhe a rota do salto, não quantas peças comer.

**Uma sequência sem escolha resolve num toque só.** Quando o prefixo já tocado
casa com um único lance, os saltos que faltam são forçados, e o lance acontece
inteiro. Pedir mais toques aí não é oferecer uma decisão — é esconder o lance
atrás de uma pergunta sem alternativa, e era o que fazia uma captura dupla
parecer recusada: o jogador tocava na casa de destino, nada se movia, e a tela
não dizia por quê. Quando há **mais de uma rota**, os toques voltam a ser
escolha de verdade, e um aviso diz que a captura continua.

**Batalha Naval** — 8x8, quatro navios por lado (Encouraçado 4, Cruzador 3,
Submarino 3, Destroier 2). Um tiro por vez, acertar não dá direito a atirar de
novo, e navios podem encostar uns nos outros. Afundou, o nome do navio é
anunciado — é a única hora em que ele é público.

**8x8 e não 10x10**, que é o tamanho mais conhecido, porque 8x8 deixa o `Board`
inteiro servir sem uma linha nova: mesmo índice `rank * 8 + file`, mesma
coordenada "e4" na moldura, mesmas 64 casas. Um segundo sistema de coordenadas no
projeto custaria bem mais que a fileira e a coluna que faltam, e com quatro
navios (12 casas de 64, 19%) a densidade fica na mesma do 10x10 com cinco.

**O tiro sai no segundo toque na mesma casa.** O primeiro mira. Num celular um
toque perdido custaria a vez inteira, e não existe desfazer — é a mesma ideia do
"toque na peça, depois na casa" do xadrez, pelo mesmo motivo.

**Só pela internet.** Sem bot e sem os dois no mesmo aparelho: o jogo é de
informação escondida, e num aparelho só ele exigiria uma cortina de "passe o
celular" entre cada tiro, que atrapalha mais do que serve. O catálogo em
`Game.GAMES` declara isso em `modes`, e a tela de "como jogar" apaga o que não se
aplica sem precisar saber o nome do jogo.

#### O segredo mora no desenho, não no modelo

O `MatchState` guarda as **duas** frotas, e é `WatersView` que decide o que
mostrar (`own`). Parece o contrário do certo, e é a troca deliberada que mantém o
resto do app de pé: `_apply_sync` reconstrói a partida repetindo a lista de
lances, e para isso os dois aparelhos precisam derivar a mesma posição. Esconder
no modelo quebraria a reconexão; esconder no desenho não quebra nada.

O preço é confiar no cliente do outro. A alternativa — guardar o segredo de
verdade e responder tiro a tiro "acertou" — obrigaria a confiar na **resposta**
do adversário, que é uma porta bem maior para trapaça do que um cliente
modificado que espia. Num app onde as partidas nascem de um código de 6
caracteres passado a um amigo, é a troca certa.

### Ludo

Quatro cores, quatro peões cada, trilha de 52 casas e dado de 6. Sai da base só
com 6; 6 dá direito a jogar de novo; pousar em cima de peão inimigo manda ele
para a base; as saídas e as quatro estrelas são casas seguras; entrar em casa
exige número exato.

**No mesmo aparelho e pela internet.** A sala do relay passou a ter N assentos e
o aperto de mão do `Net` a contar até a mesa encher; `Game.GAMES` declara
`players: 4`, e é daí que sai o tamanho da sala.

**Uma silhueta por assento, além da cor.** Vermelho joga com peões, verde com
cavalos, amarelo com bispos e azul com torres — as mesmas peças que o xadrez
desenha, tingidas. A cor continua sendo a identidade do jogo (o curral, a trilha
e a reta final são pintados dela); a forma é a segunda leitura, para quem não
separa o vermelho do verde não ver quatro peças idênticas em dois tons. É a
mesma decisão de Metrópole, e sai sem nenhum desenho novo: as quatro escolhidas
são as que menos se confundem no tamanho de uma casa — cabeça redonda, perfil de
cavalo, mitra com fenda, ameia quadrada. Dama e rei ficaram de fora porque a
coroa dos dois é a mesma mancha nesse tamanho. Não há hierarquia nisso: os
dezesseis peões seguem sendo a mesma peça com as mesmas regras, e a forma é
crachá, não patente.

Em rede, **o assento é a cor**: quem abre é o vermelho, quem entra depois é o
verde, e assim por diante (`Game.local_seat`). Só o dono da vez rola o dado; os
outros três veem o tabuleiro andar. O dado sorteado vira lance no mesmo
instante, e é o lance que viaja — como ele carrega o dado dentro, repetir a
lista reconstrói a partida em qualquer aparelho, que é o que faz a reconexão do
Ludo ser a mesma dos outros jogos.

A partida começa quando a mesa **enche**, e não quando o segundo entra: com dois
assentos as duas coisas eram a mesma, com quatro seriam dois jogando enquanto
os outros ainda estão entrando. Enquanto isso as duas telas contam ("2 de 4
jogadores") em vez de dizer "aguardando" sem fim aparente.

#### O percurso é um número, não um tabuleiro

Ludo não é uma grade de casas ocupadas: é um percurso, e o que importa de cada
peão é **quanto ele já andou**. `meta["prog"]` guarda 16 inteiros, um por peão:

```
0        na base          52..56   na reta final (privada)
1..51    na trilha comum  57       chegou
```

Contar da *própria* saída é o que faz as quatro cores dividirem uma trilha só
sem nenhum caso especial: a casa de um peão é `(saída_da_cor + prog - 1) % 52`, e
duas cores em progressos diferentes caem na mesma casa exatamente quando uma
captura a outra. Guardar as 225 células da cruz descreveria 16 peões com 209
zeros — e ainda assim não diria de quem é a reta final em que um peão está.

A volta **não** fecha: no passo 51 a cor entra na própria reta final, uma casa
antes de pisar de novo na casa de onde saiu. A casa logo atrás da saída de uma
cor só é visitada pelas outras três, de passagem.

#### O dado viaja dentro do lance

`generate_moves` devolve os pares **(dado, peão)** legais para os seis valores de
dado; quem rola filtra pelo que tirou. Parece estranho — ninguém escolhe o dado —
e é o que mantém todo o resto funcionando sem exceção: o lance continua sendo uma
coisa só, então `history` reproduz a partida inteira e a reconexão continua sendo
repetir a lista de lances. Quem recebe valida o lance contra a própria lista de
legais, como nos outros jogos; o que ele não pode validar é o dado, que é
aleatório por definição — mesma confiança no cliente do outro que a batalha naval
já pede.

**Rolagem sem lance possível também é lance** (peão `PASS`). Sem ela, um 3 com os
quatro peões na base sumiria do histórico e os dois aparelhos discordariam de
quem joga agora.

#### Quatro jogadores num app de dois

`MatchState.side_to_move` tem dois valores e aqui existem quatro cores. Quem está
jogando mora em `meta["turn"]` (0..3) e se pergunta a `LudoRules.turn_of()`; pelo
mesmo motivo quem venceu é `winner()`, que devolve o índice da cor, e não
`outcome()`, cujo enum não tem como responder em dois dos quatro casos.

#### O peão é o peão do xadrez, tingido

`PieceRenderer.draw_piece()` ganhou um `tint` opcional que multiplica a peça, e
os dezesseis peões do Ludo são o mesmo SVG do peão branco em quatro cores. O
contorno escuro do desenho sobrevive à multiplicação — escuro vezes cor continua
escuro —, então a peça tingida mantém a silhueta que ela tem no tabuleiro de
xadrez. Branco é o neutro da multiplicação, então os outros jogos não notam.

Fichas chapadas diriam a mesma coisa em outra língua: o app inteiro desenha peça
com o mesmo traço, e discos coloridos fariam o Ludo parecer emprestado de outro
app. Sendo a mesma textura, o dia em que o desenho da peça mudar ele muda aqui
junto.

O **ícone** do Ludo — o dado — é `assets/pieces/die_{white,black}.svg` pelo mesmo
motivo: desenhado por código ele saía com a paleta do tabuleiro (creme e marrom)
enquanto os três vizinhos na lista de jogos são brancos de contorno escuro, e a
linha do Ludo parecia de outro app. O caminho por polígono continua vivo como
rede de segurança.

#### O peão anda; o estado não

O lance é aplicado de uma vez — o `MatchState` nunca guarda meio caminho —, e
quem caminha é o desenho. `LudoView.travel()` recebe **de onde**, **para onde** e
quem foi derrubado, interpola em cima do progresso (não em pixels, para o peão
fazer a curva do braço em vez de cortá-la na diagonal) e emite `travel_finished`
quando acaba. A cena espera esse sinal antes de devolver a vez.

Um segundo tabuleiro só para a viagem discordaria do verdadeiro no primeiro bug
— e é o verdadeiro que viaja pela rede e reconstrói a partida na reconexão.

O ritmo é por **casa**, não por lance (`STEP_SECONDS`), com um pulinho a cada
uma: um 6 tem de parecer seis passos, e deslizar lê como arraste de dedo, não
como andar. Os peões em movimento são desenhados por último — passar por baixo
de quem está parado lê como ter sumido no meio do caminho.

#### Ser comido é diferente de mudar de lugar

A eliminação tem três partes, e a primeira versão só tinha a última:

1. **um anel abre na casa**, na cor de quem perdeu o peão. A captura acontece
   numa casa só e num instante só, e o dono do peão quase sempre está olhando
   para outro canto do tabuleiro; o anel marca o lugar depois de o peão já ter
   saído dele;
2. **o peão tomba** — gira uma volta inteira e encolhe enquanto voa
   (`PieceRenderer.draw_piece` ganhou um `spin` para isso). Atravessar o
   tabuleiro em pé lia como "mudou de lugar";
3. **pousa na base** e volta ao tamanho normal.

A volta **começa quando quem captura chega**, e não junto com o lance: o relógio
do capturado nasce negativo, igual à duração da caminhada, e até zerar ele fica
parado na casa dele esperando a batida. Sem isso, o efeito acontecia antes da
causa — o peão saía voando enquanto o outro ainda estava a cinco casas dali.

E `is_travelling()` conta o capturado, não só quem anda: sem ele na conta, o
dado da vez seguinte rolava com um peão ainda no ar.

#### O dado tomba, não pisca

Um dado de verdade tem **sete lugares** possíveis para um ponto, e cada face é
um subconjunto deles. A transição entre dois números é, então, os pontos que
saem encolhendo e os que entram crescendo, cada um no seu lugar fixo — que é o
que acontece quando um dado tomba de uma face para a outra.

Trocar a face inteira de uma vez dava um piscar que lia como falha de desenho;
interpolar posição faria os pontos deslizarem pela face, que não é coisa que
dado faça.

A rolagem **desacelera**: os primeiros números passam em 0.07s e os últimos em
0.24s, como um dado perdendo energia, e o morph acompanha o intervalo em vez de
ter duração fixa. É o que faz o resultado parecer o fim de um movimento, e não o
instante em que a animação foi desligada. O quique de chegada vem depois, e o
resultado é anunciado **quando o dado para**, não no fim dele: enfeite não
atrasa jogada.

O deslocamento do balanço fica guardado em variável em vez de sorteado no
`_draw`: um desenho tem de sair igual quantas vezes for chamado, e sorteando ali
o dado tremeria a cada redesenho da tela — inclusive parado.

#### Ritmo

Os tempos são grandes de propósito, e a primeira versão errou nisso: passo de
0.085s por casa, meio segundo para ler o dado, e a partida inteira parecia estar
sendo jogada por outra pessoa. Numa mesa de quatro, **três em cada quatro vezes
são de outro jogador** — se elas passam voando, ninguém acompanha a partida em
que está.

| O quê | Tempo |
|---|---|
| Passo do peão, por casa | 0.15s |
| Volta do capturado à base | 0.55s |
| Rolagem do dado | 0.95s |
| Leitura do número, antes do lance | 0.95s |
| Respiro depois do lance | 0.35s |
| Pausa do bot antes de rolar | 1.1s |

A volta do capturado é mais longa que um passo porque a captura é a coisa mais
importante que acontece no Ludo, e quem precisa vê-la é o dono do peão — que
provavelmente está olhando para outro canto do tabuleiro.

#### Placar de um lado, dado do outro

Abaixo do tabuleiro, duas colunas: à esquerda como está a partida (uma faixa por
cor, com quantos peões chegaram), à direita o que fazer agora (o dado e a linha
de status). Cada metade responde uma pergunta.

Antes o placar era uma linha no topo e o dado ficava num canto do rodapé: a
linha disputava a largura da tela com as próprias cores do tabuleiro logo
abaixo, e a única coisa em que se toca na tela inteira era a menor delas.

#### Quatro jogadores num app que nasceu de dois

`MatchState.side_to_move` tem dois valores e o `Net` falava de cores. O que
mudou para o Ludo caber:

| Onde | Dois jogadores | Quatro |
|---|---|---|
| Identidade | `local_side` (branca/preta) | `local_seat` (0..3) |
| Começar | `opponent_joined(cor)` no primeiro que chega | `table_ready(seats)` quando enche |
| Quem venceu | `Ruleset.outcome()` | `LudoRules.winner()`, que devolve a cor |
| Vez | `side_to_move` | `meta["turn"]`, via `LudoRules.turn_of()` |

Os dois caminhos convivem em vez de um servir aos dois casos: num jogo de dois o
assento **é** a cor, e forçar xadrez e damas a falar em assentos trocaria um
vocabulário certo por um genérico. `Net` deriva `local_side` do assento quando a
mesa tem dois lugares — uma fonte só, em vez de quem abre escrever a sua e quem
entra ler a do `welcome`.

#### Cadeira vazia vira máquina

O `Bot` do xadrez e das damas procura por minimax, e minimax trataria o dado
como uma escolha do jogador: ele jogaria supondo que todo mundo tira o que
precisa. Uma busca honesta precisaria de nós de chance e esperança matemática —
muito maquinário para um jogo em que quatro regras de bolso jogam bem. São elas,
em `LudoRules.best_move()`: **capturar > chegar > sair da base > entrar na reta
final > andar o peão mais adiantado**, com desempate pela casa segura.

Sem níveis, e o catálogo declara isso (`bot_levels: false`): não há profundidade
de busca para regular, e "fácil / médio / difícil" seriam três nomes para o mesmo
jogador. A tela de ajustes some com a seção em vez de oferecer a escolha.

O bot preenche o que faltar, em qualquer modo:

- **solo** — você é o vermelho, as outras três cores são máquina;
- **em rede** — a sala que não enche. Três amigos numa mesa de quatro esperando
  um quarto que não vem tocam em "Começar com 1 bot", e a partida começa. O
  botão só aparece quando ele resolve um problema real: a partir do segundo
  jogador presente e enquanto houver lugar vago. Antes disso ele diria "jogue
  sozinho contra três máquinas numa sala on-line", que é o modo solo com passos
  a mais.

**Quem executa um bot é um aparelho só** — no solo o seu, em rede sempre o
assento 0. Os lances dele saem pela mesma mensagem de um lance humano, e o
histórico não distingue quem os produziu; é o que mantém a reconexão idêntica.
Dois aparelhos rolando o dado do mesmo bot dariam dois valores para a mesma vez,
e as quatro partidas divergiriam no primeiro deles.

A lista de assentos de máquina viaja no `welcome` (`bots`), e quem abriu passa a
esperar `ready` só dos **humanos** — esperar por um assento de máquina seria
esperar para sempre.

A frota viaja uma vez, antes do primeiro tiro — e de novo depois de cada
reconexão, porque ela não é um lance e o replay do `sync` sozinho reconstruiria
uma partida sem navios.

Os três jogos implementam a mesma interface (`core/ruleset.gd`). Xadrez e damas
dividem a mesma cena de partida; batalha naval tem a sua, porque não há peça que
ande — há duas grades, uma fase de posicionamento antes do primeiro lance e
metade da informação escondida. `Game.GAMES` diz qual cena é de quem.

### Metrópole

2 a 6 jogadores, 40 casas, hipoteca, construção e troca. Sem leilão — é a regra
mais esquecida na mesa e a que mais trava uma partida on-line, porque para o
turno de todo mundo para resolver uma casa que uma pessoa recusou.

#### Não é "Monopoly", e isso não é timidez

O nome, os nomes das ruas e o traçado do tabuleiro original são marca e trade
dress de terceiros. A **mecânica** não é. Então a mecânica é a clássica e o
conteúdo é próprio: oito cidades brasileiras, uma por grupo de cor, do grupo mais
barato ao mais caro — Belém, Manaus, Fortaleza, Recife, Salvador, Curitiba, Belo
Horizonte, e o azul-escuro dividido entre Leblon e Jardim Europa. As quatro
ferrovias viraram quatro **aeroportos**: no Brasil elas não dizem nada a
ninguém, e o aeroporto diz exatamente a mesma coisa que a ferrovia dizia.

#### Um turno é vários lances

Esta é a decisão que faz o jogo caber no app.

No xadrez, turno é lance. No Ludo já são duas coisas — rolar e escolher o peão —
mas cabem juntas num `Move` só porque a segunda depende inteiramente da primeira.
Aqui não cabe: rola, anda, cai, resolve o que a casa manda, constrói, hipoteca,
talvez role de novo. São decisões independentes, tomadas com informação que só
existe depois da anterior. Empacotar tudo num `Move` obrigaria a declarar o turno
inteiro antes de rolar o dado.

Então o turno é uma **sequência de lances pequenos**, e o estado guarda em que
ponto da sequência está: `meta["ph"]`, a fase. `generate_moves` responde sempre a
mesma pergunta — "o que é legal agora" — e a resposta depende da fase.

O que isso preserva, e é o motivo de ter sido feito assim: **nada mais muda.**
`history` continua sendo a lista de lances, o replay continua reconstruindo a
partida, a reconexão continua sendo repetir o histórico, o validador do outro
aparelho continua conferindo contra a própria lista de legais. Um turno vira 3 a
8 linhas no histórico em vez de 1. É o único custo.

#### Os dois acasos viajam dentro do lance

O Ludo já guarda o dado dentro do `Move`. Aqui são dois: os dados **e a carta** —
`[ROLL, d1, d2]` e `[DRAW, baralho, índice]`.

A alternativa era embaralhar com semente combinada no aperto de mão. Ela quebra
na reconexão: o `sync` manda `history` e mais nada, então a semente viraria um
segundo canal, e um segundo canal é uma segunda coisa que pode chegar errada. Com
o índice dentro do lance, repetir a lista devolve exatamente a mesma partida.

Consequência assumida: **o baralho não tem memória.** Cada carta sai do baralho
inteiro, então a mesma pode repetir. Guardar a ordem custaria 32 inteiros em
`meta` e uma pilha de descarte a sincronizar; o que se ganha é uma distribuição
levemente mais justa numa partida de duas horas. A única exceção é a carta de
saída livre, que some do baralho enquanto está na mão de alguém — e isso são dois
bits.

#### A troca é o único lance que não se enumera

Todo o resto do jogo cabe em `generate_moves`, e é assim que a tela sabe o que
oferecer, o bot o que escolher e a rede o que aceitar de fora: **pertencer à
lista é ser legal**.

Uma proposta de troca não cabe na lista. São até 2²⁰ subconjuntos de escrituras
de cada lado, vezes todo valor em dinheiro possível — a lista não existe. Então
ela é conferida por **predicado**, e `MonopolyRules.validate()` virou a porta por
onde tudo passa: lance comum, confere pertencendo à lista; proposta, confere pelo
predicado. Quem aplica um `Move` sem passar por ali está pulando as regras, e a
tela, o bot e a rede passam todos por ali.

O caminho é `[OFFER, para, dinheiro, quantas_saem, casas_que_saem…,
casas_que_entram…]`, do ponto de vista de quem propõe, com o dinheiro **com
sinal** — positivo é ele pagando. Um número só e não dois campos: a diferença é
uma só, e dois campos permitiriam preencher os dois e criar dinheiro que ninguém
tem. `offer_path()` escreve e `offered_give()`/`offered_get()` leem, para a
codificação morar num lugar só — se os dois aparelhos lessem esse caminho de
formas diferentes, as escrituras mudariam de mão de forma diferente em cada um.

**É o único momento do jogo em que quem joga não é o jogador da vez.** Com uma
proposta na mesa, quem responde é o destinatário. `actor_of()` responde isso, e
existe para a tela, o bot e a rede não terem cada um a sua ideia sobre de quem é
a decisão — quem perguntasse `turn_of` ofereceria os botões ao jogador errado, e
em rede o aparelho errado mandaria o lance.

Propor **não gasta o turno**: `meta["oback"]` guarda de onde se saiu, e uma
recusa devolve o jogador exatamente ao ponto em que ele estava. Sem isso, tentar
uma troca e ouvir "não" custaria a rolagem.

Três decisões de regra que valem registro:

- **grupo com obra não sai da mão** — nem a casa construída, nem as irmãs vazias
  dela. Passar adiante a rua vazia de um grupo que tem hotel na vizinha deixaria
  construção de pé num grupo de dois donos, e a regra de uniformidade não sabe
  desfazer isso: ela pergunta "a irmã tem menos casas que esta?" sem nunca
  perguntar de quem é a irmã;
- **a hipoteca viaja junto com a escritura, sem taxa.** A regra de mesa cobra os
  juros na hora da transferência; cobrá-los aqui abriria uma cobrança que pode
  não caber no bolso **dentro** de um lance que já mudou as escrituras de dono, e
  desfazer isso pela metade é pior que a simplificação;
- **dá para propor devendo**, na fase RAISE, e aceitar liquida a dívida. É o
  momento em que a troca vale mais: vender uma cor a quem a quer rende mais que
  hipotecá-la, e é a última saída de quem está quebrando.

O bot **responde, e não propõe**, e isso é deliberado. Um bot que propõe precisa
de um freio contra o laço óbvio — proponho, você recusa, proponho de novo — e o
freio é uma contagem de propostas por turno em `meta`, sincronizada e testada,
para um ganho que é conversa entre máquinas. Respondendo, ele soma o preço de
tabela dos dois lados e aceita o que o deixa mais rico, com uma única distinção:
fechar uma cor, ou perder uma fechada, vale o dobro. Sem ela o bot troca a
terceira rua de um grupo dele pela primeira de um grupo alheio — a pior troca do
jogo, feita ao preço nominal certo.

A **mesa de troca** (`ui/monopoly_trade.gd`) é a única superfície do jogo que
ocupa a tela inteira: são duas listas de escrituras e um valor, e o painel
flutuante tem 168 de largura. Quem propõe monta e quem recebe lê **na mesma
tela** — as duas mostram exatamente o mesmo, e o que muda é se as linhas aceitam
toque e o que os botões do rodapé dizem. Duas telas separadas custariam duas
montagens, e uma delas ficaria para trás na primeira mudança de regra — bem na
pergunta que quem responde precisa poder confiar: "estou vendo a mesma proposta
que ele montou?".

As colunas são sempre do ponto de vista de **quem propõe**, inclusive na tela de
quem responde: é a mesma direção do lance, e inverter a leitura faria a tela e o
histórico contarem a mesma troca ao contrário. O rótulo diz o nome de cada um.

O botão que abre a mesa fica na **coluna da esquerda**, e não na barra de ações:
a barra responde "o que esta fase pede de você" e se refaz a cada rolagem, e
propor uma troca não é o que a fase pede — é algo que se pode fazer em quase
qualquer ponto do próprio turno, e que abre outra tela em vez de jogar um lance.
Na barra também não caberia: a fase da cadeia já ocupa os 112 de altura com três
botões.

#### Em rede

Cada aparelho é um assento, e só quem tem a decisão do momento vê botão — a
decisão sai de `actor_of()`, pelo motivo acima. O que viaja é o lance, como nos
outros jogos, e os dois acasos vão dentro dele; repetir `history` reconstrói a
partida, que é o que faz a reconexão ser a mesma de sempre.

Dois cuidados existem só aqui, e os dois são sobre **acaso duplicado**:

- a carta é sorteada por **um aparelho só**, o de quem está na fase de tirar. Se
  os quatro sorteassem ao receber o lance de quem pisou na casa de Sorte, cada um
  veria uma carta diferente;
- os bots são jogados pelo assento 0, sempre — a mesma regra do Ludo.

E um cuidado que os outros jogos não precisaram: **os lances que chegam entram
numa fila.** Um turno aqui dura segundos de animação — dado girando, peão andando
— e nesse tempo o aparelho de quem joga em seguida já pode ter mandado o dele.
Aplicar direto o descartaria, e um lance descartado é uma partida que diverge em
silêncio.

O **formato** (até a falência, ou N rodadas) é escolhido por quem abre e viaja no
`welcome` como `Net.option` — um número por jogo, genérico e sem nome de jogo,
porque `net_link.gd` não conhece jogo nenhum. Duas mesas com limites diferentes
não seriam a mesma partida, exatamente como dois relógios diferentes; e o erro só
apareceria na rodada em que uma delas acabasse.

#### A tela de fim

`MonopolyResult` cobre a tela com o vencedor e o **patrimônio final de todo
mundo**, inclusive de quem quebrou — sumir da lista faria uma mesa de seis
parecer ter tido quatro.

A tabela existe por causa do formato por rodadas: ali o vencedor é o maior
patrimônio, e esse número não aparece em lugar nenhum durante a partida — a
coluna da esquerda mostra o **caixa**, que é outra coisa. Anunciar o campeão sem
a tabela seria anunciar o resultado de uma conta que ninguém viu ser feita.

"Jogar de novo" só existe fora da rede. Revanche é conversa de dois e a mesa tem
até seis; quem quer jogar de novo em rede abre outra sala. O botão sai em vez de
prometer o que não há — mesma decisão do Ludo.

#### Em 3D, e o que isso quer dizer aqui

É o único jogo 3D do app. Ele vive num `SubViewport` dentro de uma tela que
continua sendo `Control`, então tema, botões, aviso e área segura seguem
funcionando por cima sem saber que há 3D embaixo.

**O que é plano é textura; o que tem altura é volume.** O tampo inteiro — casas,
faixas de cor, barras de dono, nomes, preços — é desenhado por `MonopolyFace` num
`SubViewport` de 1536² e colado como albedo de um plano. Peões, casas e hotéis
são malhas de verdade, de pé, com sombra.

A divisão não é estética, é de custo. Texto em 3D custa 80 `Label3D` que
precisariam ser reorientados a cada giro de câmera; sombra pintada numa textura
custa brigar com a sombra real que a luz projeta. Cada coisa fica do lado em que
é barata — e o desenho 2D que já existia virou a textura em vez de ser jogado
fora.

A geometria é **uma só**: `MonopolyFace.tile_rect()` é estática e recebe a
escala, então o `_draw` a consulta em pixels e o mundo 3D a consulta em unidades.
Duas tabelas de coordenadas seriam duas verdades sobre onde fica a casa 19, e a
casinha de plástico pousaria ao lado da faixa de cor pintada em vez de em cima
dela.

**Perspectiva**, e a ortogonal foi tentada primeiro. O argumento dela era bom —
duas casas do mesmo tamanho pareciam do mesmo tamanho — e o resultado lia como o
desenho 2D inclinado: sem convergência não há profundidade, e sem profundidade
não há motivo para o jogo ser 3D. A comparação "quanto ele construiu" se resolve
no painel, onde os números estão escritos, e não medindo casinhas na tela.

A **sombra** é o que diz que a peça tem altura, então o sol é rasante (-38°) e
não a pino: a pino ele projeta a sombra debaixo da peça, onde ela não é vista.

O enquadramento depende do formato da **janela**, que não é o da tela: a coluna
dos jogadores come um quinto da largura, e o que sobra é bem mais quadrado que
16:9. O `fov` do Godot é vertical, então a largura disponível encolhe junto — uma
distância afinada num retângulo largo corta o tabuleiro pelos lados assim que ele
entra na tela de verdade. As duas exigências são calculadas e vence a maior.

#### Uma peça por jogador

Chapéu, carro, avião, bola, barco e bota — uma por assento, e a **cor continua
sendo a do jogador**. As duas coisas juntas, e não uma ou outra: a cor é o que
liga a peça à faixa da coluna da esquerda, e a forma é o que se reconhece de
relance num anel com seis peças espalhadas. A cor sozinha falha em quem não
distingue vermelho de verde; a forma sozinha obrigaria a decorar qual é a sua.

As seis silhuetas foram escolhidas para **não se confundirem vistas de cima**,
que é de onde a câmera olha: disco com aba, retângulo com rodas, cruz, esfera,
casco com vela triangular, e um "L" deitado.

Cada uma é meia dúzia de caixas, cilindros e prismas. É a mesma decisão do peão
que elas substituem e ela se sustenta melhor aqui: o estilo é de brinquedo de
plástico, que é o que primitivas produzem sem esforço, e o que se lê a 42° de
inclinação é a silhueta, não o detalhe. Uma malha importada custaria o arquivo no
repositório, a licença a conferir, a escala e a orientação a acertar peça por
peça, e o tingimento por jogador — que numa malha pronta é sobrescrever o
material dela e torcer para o mapa de UV não depender da cor.

Elas **apontam para onde se anda**: `tile_along` é a direção em que os índices
crescem, e é a mesma conta que gira a câmera. O carro anda de frente, o avião voa
para onde vai, e o anel passa a ter sentido em vez de ser uma coleção de objetos
parados. A peça vira ao entrar na casa nova e não no meio do salto — dobrar a
esquina no ar faz o carro girar em torno do próprio eixo entre duas casas.

Uma escala na raiz da peça, e não medidas maiores uma a uma: as proporções
internas foram desenhadas umas em relação às outras — a roda cabe sob a
carroceria, a vela cabe no mastro — e mexer nelas para a peça crescer é a forma
de quebrar todas de uma vez.

#### O anel se reconhece, não se lê

Uma rua diz o grupo dela pela faixa de cor, e é a única coisa que se precisa
saber olhando o tabuleiro. As outras nove espécies de casa não tinham nada além
do nome escrito num retângulo de 127 pixels — e nome escrito obriga a **ler**
quarenta casas para achar a que interessa.

Cada uma ganhou um símbolo na borda de dentro, onde a faixa de cor fica nas ruas:
"?" na Sorte, baú no Cofre, avião no aeroporto, lâmpada e gota nas companhias,
moeda no imposto, grades na cadeia, grades com seta no "vá para a cadeia", pausa
no Descanso, seta na Partida. Nenhuma casa tem faixa **e** ícone, então os dois
nunca disputam o mesmo lugar.

Qual companhia é a lâmpada e qual é a gota sai da **ordem no tabuleiro**, não do
nome escrito: comparar strings penduraria o desenho no texto de
`monopoly_board.gd`, e renomear uma casa apagaria o ícone dela sem aviso.

#### O miolo

Eram nove unidades de bege — um quinto da área do tabuleiro sem nada, o que num
tabuleiro de papelão nunca acontece. Agora tem o nome do jogo numa faixa
diagonal e as molduras dos dois baralhos na outra diagonal, com as pilhas de
carta de verdade em cima delas.

As pilhas não são enfeite: elas são **de onde a carta vem**. Até aqui uma casa de
Sorte fazia um texto aparecer no aviso sem nenhuma origem visível na mesa. Cada
pilha são duas caixas — a borda colorida embaixo e uma carta clara em cima —,
porque uma caixa de cor só é uma placa de plástico, e a carta de cima é clara em
qualquer jogo.

Tudo em diagonal, como no tabuleiro de mesa, e pelo mesmo motivo dos cantos: com
a câmera girando não existe orientação certa para os quatro lados, e a diagonal
fica igualmente torta para dois em vez de de cabeça para baixo para um.

Os sinais dos dois ângulos parecem trocados e não são: em espaço de desenho `+y`
aponta para baixo, então um giro positivo leva o texto para a mesma diagonal em
que os baralhos estão — que foi exatamente como a primeira versão saiu, com o
nome do jogo passando por dentro das duas pilhas.

O lugar de cada baralho sai de `Face.deck_spot()`, a mesma função que pinta a
moldura. Duas coordenadas seriam duas ideias de onde é o baralho, e a pilha
pousaria ao lado do próprio desenho.

#### O que faz a cena parecer um brinquedo numa mesa

Quatro coisas, e nenhuma é modelagem:

- **a mesa.** Um plano grande e fosco embaixo de tudo. Sem ele a caixa flutua num
  vazio da cor do fundo do app, e a única sombra da cena é a das peças no próprio
  tampo — o tabuleiro inteiro fica sem peso. E ela precisa ser mais clara que o
  fundo: com os dois quase iguais a sombra que a caixa projeta não tem onde
  aparecer, e a mesa deixa de servir para a única coisa que faz;
- **o lábio.** O corpo da caixa é mais estreito que o tampo, então a superfície
  impressa sobra por cima dele, como a tampa de uma caixa de jogo. Com os dois do
  mesmo tamanho a peça lia como uma placa maciça encostada na mesa;
- **a curva filmica e um empurrão de contraste e saturação.** A linear satura os
  claros de forma abrupta — o tampo bege sob o sol chegava ao branco de chapa e o
  texto perdia contraste ali. E o empurrão é o que separa "cores de plástico" de
  "cores de material padrão" sem tocar em cor nenhuma uma a uma, que é onde a
  estética de brinquedo é mais barata de obter;
- **a sombra macia.** Sombra dura de sol pontual em peça de dois centímetros
  desenha um recorte de papel ao lado de cada uma.

#### A câmera anda atrás do peão da vez

Ela fica perto, **atrás** de quem está jogando, e olha no sentido em que ele
anda: o peão caminha para dentro da tela em vez de atravessá-la de lado. Como o
eixo do giro é a direção da caminhada e não o lado do tabuleiro, ela vira sozinha
a cada canto do anel.

O preço é a legibilidade do tampo — a fileira em que o peão está passa a ser vista
de enfiada, com o texto correndo para longe. É aceitável porque é exatamente isso
que o painel da direita mostra em letra grande: o tabuleiro não precisa ser lido
de relance quando há uma escritura aberta ao lado.

A mira é "à frente do peão" **puxada para o meio do tabuleiro**. Só à frente, ela
sai do tampo toda vez que ele se aproxima de um canto, e metade da tela vira
fundo preto. A primeira correção foi prender a mira numa caixa dentro da borda —
e a trava brigou com o avanço, empurrando a mira para *trás* do peão, que passou
a aparecer no fundo do quadro. A interpolação para o centro faz as duas coisas
com um número só, e de brinde desliza o peão para o lado oposto ao centro — que,
com a câmera na direção da caminhada, é a esquerda da tela, longe do painel.

O acompanhamento é amortecido. Colada, a câmera segue o peão — que **pula** entre
casas — e o tabuleiro inteiro passa a pular junto.

`follow = -1` volta ao enquadramento do tabuleiro inteiro, que gira por assento e
respira com o giro: a silhueta de um quadrado girado de θ mede `|cos θ| + |sin θ|`
lados, um no repouso e √2 a 45°. Nenhuma tela usa hoje — a de fim de partida
escurece o tabuleiro em vez de reenquadrá-lo, porque o que ela quer que se leia é
a tabela de patrimônio.

#### E dá para pegar a câmera na mão

Um dedo gira e inclina, dois dão zoom, e a roda do mouse também — o que separa
**tocar numa casa** de **girar a mesa** é a distância: os dois gestos começam
idênticos, com um dedo pousando, então a decisão só pode ser tomada depois, e
doze pixels a tomam.

A folga é medida contra **onde o gesto começou**, e não contra o passo anterior.
Um arrasto lento entrega dez eventos de um pixel cada, e comparar passo a passo
nunca alcança o limiar: o gesto ficaria sendo toque para sempre, girando a mesa
sem nunca abrir a casa.

O primeiro arrasto **tira a câmera do automático** — com o acompanhamento
puxando para o peão da vez, a tela estaria brigando com o dedo. Ela volta sozinha
quando uma **caminhada começa**, que é o momento em que a câmera automática vale
o que custa e o único em que o jogador certamente quer olhar para outro lugar: o
peão dele está andando. E volta por toque no "Recentrar", que aparece no canto de
baixo à esquerda exatamente enquanto ele serve para alguma coisa — sem ele, uma
mesa girada é indistinguível de uma mesa quebrada.

Na mão do jogador a mira **desliza para o meio do tabuleiro**. Orbitar em volta
do peão pareceria certo e não é: afastando de um canto, o tabuleiro sai do quadro
e metade da tela vira fundo. Em volta do centro, a distância sozinha resolve "ver
a casa" e "ver o anel inteiro" — e o deslize evita o salto de quem pegou a câmera
com o peão enquadrado.

A inclinação é travada entre 20° e 74°. Abaixo, as construções da fileira da
frente tapam o tabuleiro inteiro; acima, a perspectiva some e a mesa vira o
desenho 2D — que é justamente o que o 3D veio resolver.

O giro manual **não é amortecido**, ao contrário do automático: aqui o dedo é o
alvo, e interpolar para ele acrescentaria um atraso entre a mão e a mesa.

#### Isso obrigou a desfazer uma decisão do desenho 2D

No 2D os quatro lados eram orientados para quem olha a tela: os dois horizontais
a zero e os dois verticais a ±90°, tudo o mais legível possível de uma posição
só. Na tela de um celular em pé, certo. Com a câmera girando, errado — a conta na
tela é `ângulo_no_tampo + giro_da_câmera`, e com os quatro lados quase iguais o
lado que fica **de frente** aparece invertido.

Agora os quatro estão a 0, 90, 180 e 270, como num tabuleiro de mesa. Os quatro
cantos vão na **diagonal**, no meio do caminho entre os dois lados a que
pertencem: alinhá-los a um dos dois deixaria "Partida" e "Cadeia" — as casas mais
lidas do tabuleiro — de cabeça para baixo para metade das cadeiras.

A câmera consulta `side_angle()` e não `text_angle()`: o canto tem texto na
diagonal, e parar a 45° ao passar por ele seria um solavanco no meio da volta.

#### A tela: coluna, tabuleiro, painel flutuante

Três superfícies, uma pergunta cada.

**Coluna da esquerda** — "como está a partida": um jogador por faixa, com cor,
caixa e quantas escrituras. Sempre visível, porque comparar seis jogadores é o
que se faz o tempo todo. Só a faixa de quem joga fica preenchida; seis cartões
acesos competiriam entre si, e a primeira pergunta que a coluna responde é "de
quem é a vez". A cor é a mesma que tinge o peão, e é o único elo entre a coluna e
o tampo — sem ela, achar o próprio peão exigiria contar assentos.

**Painel flutuante à direita** — "onde eu caí" e "o que eu tenho", na mesma
superfície. As duas mostram uma escritura; o que muda é como se chegou nela.
Duas telas separadas custariam duas navegações num celular deitado.

Ele **flutua** sobre o tabuleiro em vez de ocupar uma terceira coluna: o
tabuleiro é quadrado e a tela é deitada, então uma coluna própria o encolheria
para preencher um espaço que fica vazio a maior parte do tempo — e o canto de
cima à direita de um tabuleiro em perspectiva é a área menos usada da tela.

A escritura mostra a **tabela de aluguel inteira**, não só o valor de agora. O
valor de agora responde "quanto eu pago", que a tela cobra sozinha; a tabela
responde "vale a pena construir aqui", que é a única decisão de verdade que este
jogo oferece e não se toma de cabeça. O degrau em que a casa está fica aceso e os
outros são projeção.

Largura e altura do painel são **fixas**. O conteúdo vai de uma linha ("Descanso:
não acontece nada") a onze, e um painel que muda de tamanho a cada casa arrasta o
olho para o lado a cada rolagem de dado. O corpo rola por dentro; o cabeçalho e
os botões ficam onde estão.

Os botões de ação só existem quando o lance existe — um botão cinza que nunca
acende ensina a ignorar a fileira inteira. E quem decide se ele existe é
`generate_moves`: o painel **pede**, e a construção uniforme, a hipoteca com o
grupo em obras e o caixa curto são conferidos num lugar só, o mesmo que a rede e
o bot consultam.

#### A barra muda com a fase

Embaixo do painel ficam os dois dados e **o botão do momento** — não uma fileira
fixa. Em Metrópole quase todo instante tem uma ação só que faz sentido, e as
outras nem existem: uma fileira fixa exigiria acinzentar cinco botões para
acender um, o que ensina a ignorar a fileira inteira.

Quem decide o que aparece é `meta["ph"]`, a mesma fase que as regras consultam
para dizer o que é legal. A tela não tem uma segunda ideia sobre em que ponto do
turno a partida está.

Os dois dados são decididos **juntos, antes** de girar: o lance é `[ROLL, d1,
d2]`, uma coisa só, e dois dados sorteando cada um por conta produziriam um lance
que não existe até os dois pararem. `DieView` ganhou `roll_to(valor)` para isso —
e é o mesmo método que vai animar um dado que chegou pronto pela rede.

Esperar os dois é um sinal local com contador, e não `await` de um e depois do
outro: os dois giram pelo mesmo tempo e param no mesmo quadro, em ordem que não
se controla — quem espera em sequência trava quando o segundo pousa primeiro.

A carta de Sorte ou Cofre é tirada **sem botão**. O jogador não escolhe qual sai,
e apresentar isso como escolha é pedir um toque cuja única resposta possível é
"ok" — a mesma decisão da rolagem sem lance possível no Ludo. O sorteio é feito
entre as cartas que `generate_moves` oferece, e não por índice cru: a de saída
livre some do baralho enquanto está na mão de alguém.

#### O bot: seis regras de bolso, um lance por vez

O `Bot` de busca do app não serve aqui, e não é questão de ajuste: ele trataria
os dados como escolha do jogador e procuraria a linha em que todo mundo tira o
que precisa. Uma busca honesta precisaria de nós de chance sobre 36 rolagens
**e** de um modelo de economia. Mesma decisão do Ludo — meia dúzia de regras de
bolso joga razoavelmente.

Rolar e tirar carta **não são escolhas**: são acaso, e o bot sorteia. O resto:

- **compra** quando sobra reserva, ou quando a compra **fecha uma cor** — fechar
  um grupo vale ficar sem caixa, comprar a terceira avulsa de um grupo alheio
  não;
- **constrói** pelo salto de aluguel por unidade gasta, que é o que separa
  construir no laranja de construir no marrom com o mesmo dinheiro;
- **na cadeia**, usa a carta (de graça), paga fiança só com caixa folgado, senão
  tenta a dupla. Preso é bom quando o tabuleiro está cheio de hotéis alheios;
- **devendo**, hipoteca antes de vender casa — hipotecar é reversível por 10%,
  vender devolve metade e não volta atrás — e prefere o que rende mais por lance,
  fora de um grupo fechado, porque hipotecar uma cor completa desliga o aluguel
  dobrado das irmãs também.

Ele decide **um lance por chamada**, e a tela pergunta de novo. Assim ele
constrói três casas em três lances visíveis, e a heurística não precisa saber
quantas construções cabem num turno — ela responde "e agora?" e é perguntada
outra vez.

A reserva de caixa existe porque a falência quase nunca vem de uma compra ruim:
vem de comprar tudo e cair num aluguel duas casas depois.

#### A casa responde três perguntas, não dez

O tabuleiro de papelão põe nome, preço, aluguel e as quatro linhas da tabela numa
casa só, e consegue porque é uma mesa vista de 40 cm. Numa tela de celular a casa
da borda tem cerca de 33 unidades de largura; insistir na tabela produziria quatro
linhas de 5 pixels que ninguém lê e que ainda escondem o que importa.

Então a casa responde só o que se pergunta **olhando o tabuleiro**: de quem é (a
barra de cor do dono, na borda de fora), o que tem construído (as casinhas sobre
a faixa do grupo, na borda de dentro) e como se chama. Preço, aluguel e tabela
aparecem no painel, ao tocar — que é a mesma pergunta que se faz pegando a
escritura da mão do dono.

As duas tiras nunca competem porque estão em bordas opostas: o grupo se lê
seguindo o anel por dentro, a propriedade se lê pela moldura de fora.

O corpo da fonte encolhe até caber em vez de ser cortado — "Espinhei" parece um bug do desenho, "Espinh." dois pontos menor
parece um nome comprido. O teto do corpo sai do tamanho da casa e não do tamanho
da palavra: sem ele, "Sorte" aparecia no dobro do corpo de "R. Vermelho" na casa
ao lado e o anel virava uma colcha de tipografias.

#### Deitado, e por que isso são duas coisas

É o único jogo do app que gira o aparelho. O tabuleiro é um anel quadrado cercado
de painéis de texto; em retrato ele fica com metade da largura da tela enquanto
sobra faixa preta em cima e embaixo.

Trocar só a orientação **estraga a escala**. Com `stretch/aspect="expand"` o fator
é `min(largura/432, altura/768)`; num aparelho 2400x1080 deitado isso dá 1,4 em
vez dos ~2,5 de retrato, e a base vira ~1714 unidades de largura. Como fonte,
margem e raio estão todos escritos para uma tela de 432, o resultado é a UI
inteira encolhida no meio de um oceano de espaço. Então a base gira junto:
768x432 (`ui/orientation.gd`).

Quem gira é a cena da partida; quem **desgira** é `Game.reset_to_menu()`, por onde
toda saída passa. Pôr isso em cada `_leave()` seria uma tela nova esquecendo um
dia, e o menu abrindo deitado sem ninguém entender por quê.

`SafeAreaMargin` não precisou de nada: ele já lê os quatro lados separados e
reage a `size_changed`, então o recorte da câmera indo para a lateral já estava
tratado.

### Uno

2 a 6 jogadores, 108 cartas, mão oculta. Sem tabuleiro: o que existe é um monte
de compra, um descarte e uma mão por assento — tudo em `meta`.

#### O acaso mora na semente, não em `randi()`

O embaralhamento inicial precisa ser igual nos N aparelhos **antes** do primeiro
lance, e não existe lance nenhum onde ele pudesse viajar; e a compra acontece
várias vezes por turno, então mandar cada carta comprada dentro do `Move`
publicaria a mão de quem comprou. Então o gerador é um xorshift de 32 bits
guardado em `meta`, semeado por um número que em rede chega no `welcome`. Duas
partidas com a mesma semente são o mesmo baralho, e repetir o histórico
reconstrói tudo — a reconexão continua sendo a mesma dos outros jogos.

Vale para o **rembaralho** também, e ali é onde o arquivo erraria mais caro: o
monte que acaba no meio da partida é refeito a partir do descarte pelo mesmo
gerador. Um `randi()` solto ali faria os N aparelhos divergirem em silêncio, numa
partida longa, sem nada falhar.

Consequência assumida: **a mão não é segredo do modelo.** Todos os aparelhos
derivam todas as mãos da semente, como na batalha naval — é o desenho que
esconde. Guardar o segredo de verdade obrigaria a confiar na resposta do outro
lado ("comprei uma carta, confie em mim") e mataria o replay. Por isso **não há
modo mesa**: seis mãos ocultas num aparelho só pediriam uma cortina a cada turno.

#### O grito, numa mesa que não é em tempo real

Gritar UNO é a regra que menos cabe num jogo por turnos: na mesa de verdade a
denúncia vale para quem vir primeiro, e aqui não existe "ao mesmo tempo" —
existe a vez de alguém.

O desenho é este: gritar é um **lance livre**, oferecido a quem está com duas
cartas e prestes a ficar com uma. Ele não gasta a vez — quem grita ainda joga a
carta no mesmo turno. Quem não gritar fica exposto, e **quem jogar em seguida**
pode pegá-lo: mais dois na mão de quem esqueceu, sem custar a vez de quem pegou.

Um denunciante e não todos, de propósito: dar a chance à mesa inteira faria um
esquecimento custar cinco denúncias em fila. E é *quem jogou por último*, não o
assento anterior na roda — depois de um pular ou de um +2 os dois são pessoas
diferentes, e o anterior é justamente quem acabou de ser passado para trás.

Receber carta apaga o grito: quem voltou a ter mão deve o anúncio de novo quando
descer a duas. A regra mora em `_give`, que é por onde toda entrada de carta
passa — escrevê-la em cada chamador seria um deles esquecendo um dia, e um
assento gritado para sempre.

#### O +2 e o +4 empilham

Quem recebe pode responder com uma carta da **mesma espécie** e passar a conta
adiante, somada; quem não responder engole tudo e perde a vez. Um +4 não segura
um +2 nem o contrário — misturar as duas deixaria uma mesa de seis acumular
catorze cartas com dois curingas no meio, que é outro jogo.

A conta é acumulada (`meta`) em vez de entregue na hora, e é isso que faz o
empilhamento existir: a entrega imediata dá o mesmo resultado quando ninguém tem
como responder, e nenhum resultado quando alguém tem — que é justamente a jogada
que faltava. Enquanto a pilha está de pé, a lista de lances legais é só
"responder, duvidar ou engolir": jogar um azul qualquer ali seria ignorar a carta
que está na mesa.

#### A dúvida ao +4

A regra oficial só deixa jogar o +4 sem carta da cor ativa na mão, e dá a quem
recebe o direito de exigir a prova. Acertou a dúvida, quem blefou engole a pilha
inteira e quem duvidou segue com a vez dele; errou, engole a pilha **mais dois**
e perde a vez. Esses dois são a razão de a dúvida ser uma decisão — sem custo,
duvidar sempre seria certo e a restrição do +4 viraria enfeite.

O veredito é calculado no instante do lance, com a mão que existia ali, e
guardado no estado. Recalculá-lo depois exigiria refazer a mão a partir do
histórico, e o histórico é justamente o que a dúvida questiona.

**O bot não duvida**, e é a mesma decisão do bot de Metrópole, que responde
trocas e não as propõe: o veredito está guardado no estado, e um bot que o lesse
acertaria todas as dúvidas da partida — o que não é um adversário, é um juiz com
a resposta no bolso.

#### A mão em leque

Uma mão de Uno passa de vinte cartas com facilidade. Em fila, vinte cartas numa
tela de 432 dão 21 px cada — menos que a largura de um dedo. Em leque elas se
cobrem, e o que sobra visível de cada uma é a faixa da esquerda, que é onde o
canto pequeno mora. O passo encolhe conforme a mão cresce, e **a última carta
nunca sai da tela** — que é o que uma fila rolável não garante sem um gesto a
mais.

O que pode ser jogado **sobe** alguns pixels e fica opaco; o resto fica apagado e
no lugar. Apagadas e não escondidas: a mão inteira é o que decide se vale
comprar, e sumir com as injogáveis esconde metade da conta.

### Sinuca

Dois jogadores, uma mesa de bar, dois formatos. É o jogo mais diferente do
catálogo, e a diferença tem um nome: aqui o lance não **é** o resultado, ele é a
**causa** dele. No xadrez "e2-e4" já descreve a posição seguinte; aqui uma tacada
é uma bola, uma direção e uma força, e o que acontece com as outras depois disso
sai de uma simulação.

#### Os dois formatos, e eles discordam no que é uma tacadeira

- **Mata-mata** — o jogo de bar de São Paulo: cinco bolas de cada cor e **nenhuma
  branca**. Quem joga escolhe uma das **próprias** bolas e taca com ela; ganha
  quem primeiro deixar o adversário sem bola na mesa. É o padrão, e é o mais
  curto;
- **Brasileira** — a regra nacional: a branca e sete coloridas de 1 a 7. Taca-se
  sempre com a branca, e a **bola da vez** é a de menor número ainda na mesa.
  Cada bola vale o número dela, a falta entrega sete ao adversário, e a mesa
  limpa decide pelo maior placar.

A diferença atravessa o arquivo inteiro, e é por isso que ela tem um nome:
`has_cue_ball()`. Com tacadeira, a bola que taca é sempre a mesma, nunca sai do
jogo e volta para a marca quando cai; sem ela, a bola que taca é uma **escolha**,
é do grupo de quem joga, e cair é perdê-la.

O formato é escolhido por quem abre e viaja no `welcome` como `Net.option`, como
o limite de rodadas de Metrópole. Duas mesas com formatos diferentes não seriam a
mesma partida.

#### No mata-mata, o objetivo é invertido — e isso resolve as regras sozinho

Ganha quem primeiro deixar o adversário **sem bola na mesa**. Parece um detalhe e
é o que faz o resto fechar sem caso especial nenhum:

- **encaçapar uma bola sua** não precisa de punição escrita. Ela sai do jogo, e
  sair do jogo é exatamente o que aproxima o outro de vencer. Um tiro no pé
  literal;
- **ficar sem bolas é perder**, e cai da mesma frase: se não sobrou nenhuma sua,
  não sobrou nada para o adversário ter de matar;
- **bater primeiro numa bola sua é falta.** Sem isso, empurrar as próprias para
  perto das caçapas seria uma tacada grátis, e o jogo deixaria de ter uma decisão
  por vez. A falta só passa a vez — não tira bola de ninguém, porque a mesa já
  pune sozinha quem erra.

As cores são **fixas desde o começo**, e não decididas pela primeira bola que
cai: aqui a cor não é um prêmio de saída, ela é de quem joga desde antes da
primeira tacada, porque é com aquelas bolas que ele taca.

#### O arranjo inicial não é um triângulo

As dez começam encostadas nas tabelas, cada cor de um lado, com duas de cada
flanqueando as caçapas do meio.

Não é estética. **Sem tacadeira não existe saída**: não há uma bola de fora para
abrir o agrupamento, e um triângulo fechado seria dez bolas que ninguém consegue
separar. Coladas nas tabelas, toda bola tem linha para alguma caçapa desde a
primeira tacada.

#### A física mora em `core/`, junto das regras

Porque ela **é** a regra. Se ela morasse na tela, o aparelho do adversário
receberia "taquei para lá com essa força" e teria de acreditar no resultado que
viesse junto — e um resultado que viaja é um resultado que pode ser inventado.
Com a simulação dentro das regras, os dois aparelhos rodam a mesma tacada e
chegam à mesma mesa, e repetir o histórico reconstrói a partida como em todos os
outros jogos. A reconexão da sinuca é a mesma de sempre, sem uma linha nova.

#### A tacada é um par de inteiros, e não um ângulo

Esta é a decisão que torna tudo acima possível.

Um lance carrega a velocidade inicial da branca em **milésimos de unidade por
segundo**, dois inteiros. Não carrega ângulo — e a diferença não é de gosto.
Ângulo obrigaria os dois lados a chamar `cos` e `sin`, e essas duas, ao contrário
de `+`, `-`, `*`, `/` e `sqrt`, **não** têm resultado garantido bit a bit entre
plataformas: a biblioteca matemática de um ARM pode devolver um último bit
diferente da de um x86. Um bit na direção vira um centímetro depois da terceira
tabela, e um centímetro é a bola entrando ou não entrando.

Então quem mira converte ângulo em vetor **uma vez**, no aparelho de quem está
jogando, e o que viaja é o vetor já quantizado. Daí para frente a simulação usa só
as cinco operações que a IEEE-754 obriga a arredondar corretamente, e as duas
mesas são a mesma mesa. O teste que persegue isso está em `tests/pool_probe.gd`:
a mesma tacada tem de parar as nove bolas no mesmo lugar, e uma mira um milésimo
diferente tem de dar uma mesa diferente — se não desse, a quantização estaria
grossa demais para o jogo ter mira.

Pelo mesmo motivo **não há efeito** (nem "inglês"): ele pediria rotação, atrito
lateral e uma integração bem mais sensível a erro, e a primeira coisa a quebrar
seria justamente a igualdade entre os dois aparelhos.

#### E não há acaso nenhum

É o único jogo do app sem sorteio: o triângulo nasce sempre igual, a física é
determinística, e a única entrada é a tacada. Não há semente para combinar nem
carta para sortear.

#### A animação é a própria simulação

A tela não recalcula nada. As regras guardam retratos da mesa a cada quatro
passos e a tela os reproduz em ordem, no mesmo ritmo em que foram gravados. Uma
segunda física no desenho seria a forma clássica de a partida animada divergir da
partida jogada — a bola entrando na tela e não entrando na regra, ou o contrário.

#### A mira é um arrasto, e ele é ao contrário

No mata-mata, o toque numa bola própria **escolhe** com qual se taca; em qualquer
outro lugar da mesa, ele começa a mira da que já está escolhida. Um botão
separado para trocar de bola seria um toque a mais para uma decisão que o dedo já
sabe apontar.

O dedo puxa **para trás** da bola, como se puxa um taco: a direção é do dedo para
a bola, e a distância é a força. Puxar para frente pareceria empurrar a bola
com o dedo, e num celular o dedo estaria justamente em cima do que ele precisa
ver.

**O taco é a barra de força.** Ele aparece atrás da branca enquanto o dedo está
na tela e recua conforme o arrasto cresce — quanta pancada vem se lê no recuo,
sem nenhum número, que é como se lê força numa mesa de verdade. Só enquanto o
dedo está na tela: um taco parado atrás da bola pediria uma direção que ninguém
escolheu ainda, e apontá-lo para um lado qualquer seria a tela inventando a mira.

Três traços saem do gesto, e cada um responde uma pergunta diferente:

1. **a linha da branca**, em latão, até onde ela para — na primeira bola do
   caminho ou na tabela. Uma linha que atravessasse a mesa inteira prometeria uma
   trajetória que não existe, que é o pior tipo de ajuda: a que mente;
2. **a bola fantasma**, um círculo vazado onde a branca encosta. É dela que sai a
   resposta seguinte;
3. **a seta da bola atingida**, na cor da própria bola. Numa batida entre esferas
   de mesma massa, a bola parada sai pela **linha dos centros** no instante do
   contato — não pela direção da tacada. É a regra de bolso que todo jogador usa,
   e a única coisa da mesa que dá para prometer sem mentir. Por isso a seta é
   curta: ela é uma direção, não uma trajetória, e a primeira tabela depois disso
   já depende de quanto sobrou de velocidade. Da cor da bola porque no mata-mata
   a pergunta não é só "para onde", é **qual** — e a preta do 7 é clareada para
   riscar o pano, senão a seta some no verde.

#### O ponto de contato não é "dois raios"

Foi o erro que a primeira versão cometeu, e ele só aparece de raspão.

A branca não para a duas bolas medidas **ao longo da mira**: ela para quando os
dois centros ficam a duas bolas de distância. No triângulo formado pela linha de
mira, pela perpendicular até o centro da outra bola e pela linha dos centros, o
recuo é `sqrt((2r)² - lateral²)` — Pitágoras. Na batida frontal os dois números
coincidem, e é por isso que o erro passa despercebido; de raspão eles se separam
por até meio raio, a bola fantasma aparece **depois** do contato, e a seta — que
nasce da linha dos centros — aponta para o lado errado. `tests/pool_scene_probe.gd`
confere os dois casos com a conta feita à mão.

#### Na boca da caçapa não há tabela

A borracha some perto de cada buraco. Sem isso ela atravessa a entrada e a bola
**quica** no lugar em que deveria cair — uma bola mandada no canto volta para o
pano, e o jogo fica com seis buracos que só engolem quem chega pelo meio.

#### O bot simula, não procura

Ele não usa o `Bot` do app. Aquele procura em profundidade contando lances
discretos, e uma tacada não é discreta: o galho seguinte depende de onde nove
bolas pararam. O daqui monta um punhado de tacadas candidatas — uma por bola na
mesa, em três forças —, **simula cada uma de verdade** numa cópia da mesa, e fica
com a que encaçapa o que interessa sem fazer falta. Um passo só, simulado, joga
melhor que uma árvore rasa sobre uma aproximação.

### Transporte: uma sala, e só

O anfitrião abre uma **sala** no relay e mostra um código de 6 caracteres. O
convidado entra dizendo o nome da sala. É isso — não há descoberta de rede,
endereço IP, hotspot nem ligação direta entre os aparelhos.

O código chega ao convidado por três canais que produzem o mesmo resultado:

| Canal | Precisa de quê |
| --- | --- |
| **Digitado** | nada além de ler a tela do outro |
| **QR Code** | câmera (plugin Android) |
| **NFC** | encostar os aparelhos (plugin Android) |

Os três terminam na mesma chamada com o mesmo código. Depois disso o caminho é
um só: `net/relay_bridge.gd`.

**Por que sala e não P2P.** Os dois aparelhos discam **para fora**, para um
servidor comum. É o único arranjo que atravessa NAT: em rede móvel os dois estão
atrás de CGNAT e nenhum aceita conexão de entrada. Discar para fora é a única
direção que sempre passa. O servidor está em [`relay/`](relay/) e não conhece
xadrez — ele emparelha dois sockets e repassa bytes.

Por que relay e não WebRTC: P2P daria conexão direta, mas exigiria mesmo assim
sinalização + STUN + um TURN de reserva, e em rede móvel boa parte das conexões
acaba caindo no TURN — que é um relay com mais etapas. Um lance tem ~40 bytes e
o jogo é por turnos: latência e banda não são o problema.

### O que saiu, e por quê

Três caminhos foram removidos. Nenhum por não funcionar.

**Nearby Connections** (Google Play Services) combinava Bluetooth, BLE e Wi-Fi
Direct sozinho e conectava dois celulares lado a lado sem rede nenhuma. Saiu por
conduta: **ligava os rádios do aparelho por conta própria** — só de abrir a tela
de entrar numa partida, o Wi-Fi era ligado à força — e custava permissão de
localização mais cinco de Bluetooth no manifesto. Um jogo de tabuleiro não tem o
direito de mexer no Wi-Fi de quem está jogando.

**ENet sobre IP + descoberta por UDP** ligava os dois aparelhos direto na rede
local. Funcionava, e mesmo assim atrapalhava: quando o anfitrião aparecia na
lista da rede, o convidado gastava três tentativas de conexão a endereços que o
Wi-Fi doméstico costuma bloquear (isolamento de clientes) antes de chegar ao
relay. A tela mostrava endereços IP — que não é o que alguém quer ler para
entrar numa sala — e o resultado prático era uma espera longa terminando no
caminho que teria funcionado de imediato.

**Hotspot local** (`startLocalOnlyHotspot`) resolvia "redes diferentes, um do
lado do outro" abrindo uma rede própria e mandando SSID e senha dentro do QR.
Era a última coisa no app a pedir permissão de localização.

O princípio que sobrou: **um caminho a mais só vale o preço quando alcança
alguém que os outros não alcançam.** Nenhum dos três alcançava — todos cobriam
casos que a sala já cobre, e cobravam permissões, código e espera por isso. O
que se perdeu de verdade é jogar com **nenhum dos dois aparelhos com internet**,
e esse caso não apareceu em nenhuma rodada de teste.

Foi essa indiferença ao transporte de `net_link.gd` — um dicionário por evento,
o mesmo protocolo em cima de qualquer coisa — que fez cada remoção caber em
apagar um arquivo e um bloco de `match`.

**Sobre substituir por Bluetooth puro:** daria, e não é barato. Nearby
Connections *é* o invólucro do Google sobre BT/BLE/Wi-Fi Direct — trocá-lo por
Bluetooth direto significa escrever um plugin Kotlin novo, com pareamento pelo
diálogo do sistema (RFCOMM) ou papéis central/periférico e descoberta escritos à
mão (BLE). Nenhum dos dois evita `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`, e o BLE
ainda pede localização no Android 11 e anterior.

Antes de investir nisso, vale responder: quantas partidas acontecem com dois
celulares lado a lado e **nenhum dos dois** com internet? Se a resposta for
"quase nenhuma", o plugin não se paga.

### Reconexão

Em rede móvel o socket morre a cada troca de célula, de Wi-Fi para dados, ou
quando a tela apaga. Sem tratamento, cada uma dessas seria uma partida perdida.

A sala fica de pé no relay por **90 segundos** depois que um lado cai, e o
cliente reconecta sozinho dentro dessa janela reocupando o mesmo assento. O
tabuleiro congela com "Conexão instável. Tentando reconectar…" em vez de
declarar a partida encerrada.

Voltando, os dois lados mandam o histórico inteiro de lances e quem estiver
atrás **reconstrói a posição do zero**, replayando desde o estado inicial. Os
dois rodam o mesmo ruleset determinístico, então a lista de lances é a única
coisa que precisa atravessar — e recomeçar do início não depende de a posição
local estar certa, que é justamente o que está em dúvida numa reconexão.

Cada lance viaja com o próprio índice na partida (`n`), o que o torna
idempotente: um lance que chega duas vezes por causa da reconexão é reconhecido
como repetido em vez de recusado como ilegal.

Detectar a queda é metade do trabalho. TCP em rede móvel não avisa: o socket
fica aberto para sempre mandando pacotes para o nada. Quem percebe é o
`ping`/`pong` da aplicação — 45 segundos de silêncio e o link é dado como morto.

#### Mesa de mais de dois: um bot no lugar, até a volta

Congelar a mesa inteira à espera de quem caiu era o 4G de uma pessoa parando o
jogo das outras três — por até noventa segundos, e depois disso a cadeira virava
máquina de qualquer jeito. Agora ela vira máquina **na hora**: o relay avisa o
`peer_left`, todos os aparelhos põem o assento em `bot_seats`, e o menor assento
humano passa a jogar por ele. Quando a pessoa volta, a cadeira sai da lista e ela
reassume a mão com o que o bot jogou já no histórico — que é o que o `sync`
entrega a qualquer um que volta. Os avisos na tela dizem as duas coisas: "Fulano
saiu. Um bot joga até a volta." e "Fulano assumiu o lugar do bot."

Numa mesa de **dois** a espera continua. Ali não sobra partida para uma máquina
preservar, e um bot jogando no lugar de quem caiu decidiria o resultado de um
contra um.

#### Quem recebe quem volta

Era **o assento 0, sempre** — e isso deixava sem resposta justamente o caso em que
o ausente era ele. O anfitrião que caía e voltava pelo código sentava no 0, a
camada de rede derivava `is_host` do número do assento, ele se achava dono de
uma sala por abrir e mandava um `welcome` novo: partida nova, **com outra
semente**, enquanto os outros seguiam na antiga — e a sala antiga sem ser apagada,
porque os outros continuavam nela.

Agora `is_host` é o papel no aperto de mão, decidido por quem chamou
`host_relay`, e quem recebe uma chegada com a partida em curso é o **menor assento
humano presente na sala**, sem contar quem chega. Todo aparelho da partida tem a
mesa inteira em memória, então qualquer um pode descrevê-la; o que precisa ser
único é quem descreve, e "o menor presente" é uma conta que todos fazem igual
sem combinar nada. Presença vem do relay, e só de chegadas de verdade
(`peer_arrived`): quem só perdeu o Wi-Fi e volta não "recebe" os três que nunca
saíram com a lista de máquinas velha dele.

O `resume` vai para a mesa inteira, e cada um responde conforme o que é: quem
nunca esteve na partida (ou teve o processo morto) abre a partida; quem caiu com
ela em memória descongela e troca histórico; quem só assistiu atualiza a lista de
máquinas e não responde nada.

#### A cadeira em disco, e o cartão de voltar

A chave do assento morava só na memória da ponte. Um celular sem bateria, ou com
o app fechado pelo sistema, perdia a chave junto com o processo — e o jogador
reabria o app numa tela cujo único gesto à mão era **criar** partida.

`Game.begin_match()` grava sala, jogo e chave em `Prefs` ao abrir toda partida em
rede. A tela inicial e a de Multiplayer mostram um cartão "Voltar para Uno"
enquanto houver partida guardada, e **todo caminho** até aquela sala leva a chave:
o cartão, o código digitado, a sala tocada na lista, o QR. Três regras decidem o
cartão:

- **cair mantém a cadeira** — o processo morreu ou a rede caiu, e não houve `bye`;
- **sair pelo botão a esquece** — é desistir, e `Game.reset_to_menu()` distingue os
  dois casos por `Net.connected`, que é o mesmo que decide se o `bye` sai;
- **a recusa definitiva a esquece** — `room_not_found` vira "essa partida já
  acabou", `room_full` vira "sua cadeira foi ocupada". Um cartão que sempre leva ao
  mesmo erro é pior que cartão nenhum. O `X` também esquece.

Do lado do relay, **quem senta sem chave ganha chave nova**. Sem isso, a cadeira de
quem caiu e foi ocupada por outra pessoa continuaria abrindo com a chave antiga:
o dono antigo voltaria derrubando o novo, o novo reconectaria com a mesma chave e
derrubaria de volta — dois aparelhos se expulsando a cada meio segundo.

### Sair não é cair

Do lado de quem fica, um oponente que toca em "Sair" e um oponente que entrou no
metrô produzem o mesmo evento: o socket do outro sumiu. Tratar os dois igual
deixava quem ficava em "Conexão instável. Tentando reconectar…" **para sempre** —
o socket local continuava vivo, a ponte nunca falhava, e o aviso de que o
oponente saiu não chegava nunca.

A diferença tem de vir de quem sai: `Net.leave()` manda um `bye` antes de fechar,
e o outro lado encerra a partida na hora.

Um detalhe sem o qual isso não funciona: o `bye` é enfileirado e o `close()`
viria logo atrás, então `RelayBridge.leave()` faz um `poll()` antes de fechar.
Sem ele o quadro morre na fila de saída e a saída volta a ser indistinguível de
uma queda.

E porque nem toda saída consegue avisar — app encerrado pelo sistema, bateria
acabando —, há uma **rede de segurança** numa mesa de dois: 95 segundos sem o
oponente voltar encerram a partida de qualquer forma. (Numa mesa maior não há o
que encerrar: a cadeira já virou máquina.) É um pouco além da carência da sala no
servidor, porque depois dela a volta já é impossível e continuar prometendo
reconexão seria mentir.

### Lista de salas abertas

A tela de entrar mostra as salas esperando alguém: jogo, ritmo, código e há
quanto tempo estão abertas. Um toque entra.

**Aparecer na lista é opt-in.** O painel de ajustes tem "Quem pode entrar", e o
padrão é **"Só com o código"**. O código de 6 caracteres sempre foi um segredo —
quem abre uma partida para um amigo não pode receber um estranho por não ter
reparado numa opção. A lista existe para achar quem você não conhece, e é uma
escolha, não um efeito colateral.

O servidor filtra antes de responder: só entram salas com anfitrião conectado e
assento de convidado livre. Anunciar uma sala cheia só renderia um `room_full`
para quem tocasse nela, e uma sala cujo anfitrião caiu é promessa vazia.

O que a lista **não** tem é nome de jogador. Isso exigiria um campo de nome no
app e viraria dado de usuário num servidor que hoje não guarda nenhum — o relay
sabe um código, um jogo e um número de ritmo, e nada mais.

`GET /rooms` devolve `{"rooms":[{code, game, tc, age}]}`. O cliente consulta ao
abrir a tela e a cada 6 segundos: uma sala aberta é uma pessoa esperando, e a
lista tem de acompanhar isso sem ninguém puxar para atualizar.

### Assistir

Xadrez e damas podem ser **assistidos**: pelo código (botão "Assistir", ao lado
de "Entrar") ou pela seção **"Ao vivo"** da mesma tela, que lista as partidas
públicas com a mesa cheia (`GET /live`, o avesso de `/rooms`). Uma sala
privada continua só de quem tem o código.

No relay o espectador é um papel à parte (`{"t":"watch"}`): não ocupa assento,
não muda a lotação, não segura viva a sala que os jogadores deixaram, e são no
máximo oito por sala. Ele recebe tudo o que os jogadores falam e **nada do que ele
manda sai do servidor** — os clientes confiam no assento que o relay carimba em
cada mensagem, e um `bye` ou um `sync` de quem só assiste encerraria ou
reescreveria a partida dos outros. O `Net` e o `RelayBridge` recusam o envio
também, para nem um bug da tela chegar à rede.

Quem chega no meio recebe uma **foto da partida** (`watch_state`): a mesa, os
nomes, o histórico de lances e qual assento joga de brancas. Quem manda é o
jogador de menor assento presente — a mesma conta de quem recebe um jogador que
volta —, sempre que o contador de espectadores muda com alguém assistindo. Uma
foto repetida é descartada como um resync que não traz nada novo.

Os jogadores veem **"N assistindo"** na barra da partida: ninguém é assistido sem
saber. A tela de quem assiste é a mesma `match.gd`, com as brancas embaixo, sem
toque, sem pré-movimento, com o resultado contado pelas cores, e seguindo a
revanche dos jogadores com as cores trocadas.

### Os três canais do código

O anfitrião publica o mesmo payload nos três, e o convidado usa o que tiver à
mão:

| Canal | Como funciona | Precisa de plugin nativo? |
| --- | --- | --- |
| **Código de 6 caracteres** | lido da tela do anfitrião e digitado | não |
| **QR Code** | gerado em GDScript puro e desenhado na tela do anfitrião | não para gerar; sim para ler com a câmera |
| **NFC** | anfitrião emula um cartão (HCE), convidado lê em reader mode | sim |

Nenhum é obrigatório: o código digitado sempre resolve. Isso é proposital — o QR
já foi carga estrutural (sem ele lido, sem senha de hotspot, sem partida) e
dependia de câmera, foco, brilho de tela e formato de payload casado nos dois
lados. Fragilidade demais para um jogo de tabuleiro.

O payload é uma linha, e agora ela é curta:

```
XDM3|chess|K7QW2M
	 jogo  código da sala
```

Antes eram sete campos — lista de endereços, porta, SSID e senha de hotspot —
porque a partida era uma ligação direta e o convidado precisava saber *onde*
estava o anfitrião. Com sala, ele só precisa saber *qual*. O QR caiu da versão 5
(37x37, com credenciais) para a versão 2 (25x25), e **um QR menos denso é um QR
que a câmera trava de longe, com a tela suja e com pouca luz** — que é a
condição real de quem lê a tela do outro celular.

O formato antigo tem sete campos e é recusado pelo `parse_payload`, o que é o
comportamento certo: melhor não entrar do que entrar lendo os campos trocados.

### Durante a partida

O anfitrião joga de brancas. Só os lances trafegam: os dois aparelhos rodam o
mesmo código de regras e **cada lado valida o lance recebido contra a própria
lista de lances legais** antes de aplicá-lo, então nenhum lado precisa confiar
no tabuleiro do outro — nem no relay no meio, que por isso pode ser um servidor
burro sem nenhuma regra do jogo. O código de 6 caracteres também é o segredo do
handshake: sem ele um estranho não entra na partida.

### No mesmo aparelho: modo mesa

Jogar no mesmo aparelho não pede rede nenhuma, e não pede passar o celular de
mão em mão: ele fica **deitado na mesa entre os dois jogadores**, e o que
pertence a quem está do outro lado aponta para lá — as peças dele e o cartão
dele, girados meia volta.

Só isso gira. O tabuleiro, as coordenadas, os destaques e o cartão de baixo
ficam parados: girar tudo seria a mesma tela ao contrário, que resolve para um
jogador e quebra para o outro.

A linha de último lance é desenhada **duas vezes**, uma de cada lado do
tabuleiro, com o mesmo conteúdo — a de cima virada, a de baixo em pé. Quem
acabou de jogar sabe o que jogou; quem precisa da informação é o outro. Uma
versão anterior mostrava só do lado de quem moveu, e isso deixava a resposta de
cabeça para baixo justamente para quem tinha a pergunta.

Em rede só existe a de cima: lá cada jogador tem a própria tela, e não há um
segundo par de olhos do outro lado do aparelho para atender.

**As coordenadas saem duas vezes.** Embaixo e à esquerda para quem está deste
lado; em cima e à direita, de ponta-cabeça, para quem está do outro. Uma
coordenada só serve para quem consegue lê-la, e com o aparelho deitado entre os
dois jogadores metade da mesa lia tudo invertido.

**Não há botão de girar o tabuleiro.** Havia, e saiu: a orientação é sempre a
certa sozinha — em rede cada jogador vê o próprio lado embaixo, e no mesmo
aparelho as peças já apontam para os donos. Um botão para corrigir uma
orientação que nunca está errada só dá ao jogador a chance de estragá-la.

### Último lance e material

Uma linha sobre o tabuleiro diz quem jogou por último e o quê; as peças
capturadas ficam no cartão de quem as tomou, com o saldo de material ao lado.

No tabuleiro, **as casas do último lance ficam verdes** — de onde a peça saiu e
onde ela está, na mesma cor. Nas damas todas as casas do salto entram, que é o
lance de verdade. A linha de texto diz *o quê*; o verde diz *onde*, e é a
pergunta que se faz primeiro ao voltar a olhar a tela.

Verde e não o latão da interface, por duas razões. O latão quer dizer "é aqui
que você age", e num lance que já aconteceu ele convidava a agir sobre o
passado. E ficava a um passo da madeira clara do tabuleiro: um destaque que só
aparece quando você procura não está destacando nada.

Mesma cor nas duas casas, e não uma para a origem e outra para o destino:
diferenciá-las responderia uma pergunta que o tabuleiro já responde melhor — a
casa com a peça é onde ela está, a vazia é de onde ela veio.

> Uma seta de origem a destino chegou a existir aqui, com anel na casa de saída
> e ponta na de chegada. Foi trocada pelo par de casas coloridas: a seta
> carregava direção que as duas casas já entregam de graça, e num tabuleiro de
> celular ela cruzava outras peças para dizer o que a presença da peça no
> destino já dizia sozinha.

A lista completa de lances existiu e saiu. Num celular em retrato ela ou rouba
altura do tabuleiro ou vira um painel que cobre a partida, e a pergunta que o
jogador realmente faz — quando volta a olhar a tela — é "o que o outro acabou de
jogar?". Essa cabe numa linha.

No xadrez a notação é **algébrica abreviada em português** — `e4`, `Cf3`,
`exd5`, `O-O`, `a8=D+`, `Ta8#` — com as letras da interface (Rei, Dama, Torre,
Bispo, Cavalo). Inclui a desambiguação da norma, na ordem certa: coluna
(`Cbd2`), depois linha (`T1d3`), depois a casa inteira. Nas damas cada casa é
uma coordenada e os saltos ficam encadeados: `c3-d4`, `c3xe5xg7`.

A notação mora no `Ruleset` e não na tela, porque é regra de jogo — xadrez
desambigua por peça, damas encadeia saltos. A tela só empilha strings.

> As damas têm uma notação tradicional que numera as 32 casas escuras de 1 a 32,
> e ela não foi usada: o ponto de partida da numeração muda entre federações, e
> um número lido no sentido errado é indistinguível de um certo. A coordenada não
> tem essa ambiguidade.

Nada disso é estado novo. `MatchState.history` continua sendo a única verdade, e
tanto a notação quanto as capturas são **derivadas** dela — por isso o resync
depois de uma reconexão reconstrói as duas junto com o tabuleiro. Uma lista de
lances que só soubesse crescer sobreviveria ao resync descrevendo outra partida.

### Revanche

Em rede, revanche é **convite, não ordem**: quem pede vê "Aguardando o
oponente…", e quem recebe escolhe entre aceitar e recusar. Antes um toque
reiniciava os dois lados na hora, e o outro jogador era arrastado para um
tabuleiro novo sem ter sido consultado.

Aceita, **as cores trocam**. Sem isso o mesmo jogador começa de brancas partida
após partida, que é meia vantagem repetida para sempre.

Dois toques quase simultâneos viram acordo em vez de dois pedidos empacados: se
o convite do outro chega enquanto o nosso está pendente, isso *é* a concordância
que o convite pedia.

Por causa da troca, **o assento não diz a cor**. A conferência "este lance é de
quem tem a vez" deriva a cor do assento a partir do nosso assento e da nossa cor
atual (`_seat_of`); a conta fixa "quem abriu joga de brancas" recusava o
primeiro lance de toda revanche.

No mesmo aparelho a revanche é imediata — os dois jogadores estão ali, e pedir
confirmação a quem está do outro lado da mesa seria perguntar duas vezes.

### Relógio

Damas não tem relógio, e a regra mora em `Game.supports_clock()` e não na tela
que oferece a escolha: assim nenhum caminho — sala pela lista, QR, NFC,
revanche — consegue ligar um cronômetro num jogo que não o usa. A seção de ritmo
some do painel de ajustes quando o jogo escolhido é damas.

Cinco ritmos — sem relógio (padrão), 1:30, 3 + 2, 5 min, 10 min — escolhidos num
painel que abre entre "quero jogar" e o tabuleiro, e o tempo restante ocupa o
canto direito do cartão de cada jogador, no lugar da etiqueta "SUA VEZ". As duas
diriam a mesma coisa, já que o cartão aceso indica a vez, e o número diz mais.
Abaixo de 20s aparecem os décimos e a etiqueta fica vermelha.

O painel aparece em "Criar partida" e em "Jogar no mesmo aparelho", nunca em
"Entrar": quem entra recebe o ritmo do anfitrião no handshake, e oferecer ali a
escolha seria oferecer uma decisão que não é dele. Ele existe por causa do
relógio, mas a forma é a que aguenta o resto — cada regra futura vira uma
legenda e um grupo de opções dentro do mesmo `VBox`, sem tela nova a cada uma.

Os ajustes ficaram atrás da ação, e não soltos no menu: no menu eles disputavam
atenção com "Criar partida" mesmo quando ninguém ia mexer neles, que é a maioria
das vezes.

Só o lado da vez consome tempo. O incremento entra depois do lance, para quem
jogou: sem ele os últimos lances de uma partida de 3 minutos viram corrida de
toque, não de xadrez.

**O relógio para durante uma reconexão.** Não é detalhe: sem isso, quem trocasse
de Wi-Fi para 4G no meio da partida voltaria já derrotado no cronômetro — e o
relay foi construído justamente para essa troca não custar a partida.

Cair no tempo é derrota, **exceto** quando quem ganharia não tem com que dar
mate — rei sozinho, ou rei com um bispo ou um cavalo. Aí é empate, pela norma
(`ChessRules.has_mating_material`). Sem essa verificação um empate teórico
viraria derrota inventada pelo cronômetro.

Em rede, os dois relógios viajam dentro de cada lance, e não só o de quem jogou.
Isso é exatamente certo e não redundância: o lado que **não** está para jogar não
correu em nenhum dos dois aparelhos desde a última troca, então a cópia que o
adversário tem dele está atual. Uma mensagem por lance zera a deriva dos dois.

O ritmo é escolhido por quem hospeda e viaja no `welcome` do handshake. Dois
relógios diferentes não seriam a mesma partida, então essa é a única resposta
possível.

### Contra o bot

Xadrez e damas contra um adversário local, em três níveis — **Fácil, Médio,
Difícil** — e com a cor escolhida no mesmo painel de ajustes que já existia. Não
precisa de rede: o bot mora no aparelho.

**A busca não conhece nenhum dos dois jogos.** `core/bot.gd` pede lances,
aplica, e pergunta quanto a posição vale — as três coisas pela interface
`Ruleset`. O que sabe xadrez é `ChessRules.evaluate()`; o que sabe damas é
`CheckersRules.evaluate()`. Um terceiro jogo ganha bot escrevendo uma função,
sem tocar na busca.

Minimax com poda alfa-beta, aprofundamento iterativo e busca de sossego
(*quiescence*). A última é a que mais se sente: sem ela o bot mede a posição no
meio de uma troca — come o peão defendido no último lance da busca, marca o
ponto e nunca vê a recaptura. É o sintoma clássico, e faz um bot com avaliação
correta parecer aleatório.

#### O limite é tempo, não profundidade

Cada nível tem um teto em milissegundos (250 / 900 / 2500), e não uma
profundidade fixa. É a decisão que faz o bot funcionar fora da máquina de
desenvolvimento: uma profundidade que sai em meio segundo aqui leva dez num
celular antigo, e um teto de tempo se traduz sozinho — o aparelho lento procura
menos fundo e responde na mesma hora. O aprofundamento iterativo é o que torna
isso utilizável: estourar o tempo no meio de uma rodada não deixa o bot sem
resposta, deixa com a resposta da rodada anterior.

#### Numa thread, e por quê

A busca roda numa `Thread`, sobre um clone do estado e com uma instância própria
das regras. Não é otimização prematura: dois segundos e meio na thread principal
seriam a tela congelada, o relógio parado e o toque ignorado — a impressão exata
de um jogo travado. Sair da partida enquanto ele pensa pede a desistência e
espera; abandonar a cena com a thread viva derruba o processo, e é uma queda que
só aparece em quem fecha a partida no segundo errado.

O lance volta e é **revalidado contra a lista legal da cena**, como um lance que
chega pela rede. A busca trabalhou sobre um clone, e um clone é uma posição
paralela: ela *deveria* ser a mesma, e "deveria" não é o que se aplica no
tabuleiro.

#### O que faz um nível ser fácil

Não é só procurar menos fundo. Mesmo a dois lances de profundidade o bot nunca
deixa uma peça de graça, e para quem está aprendendo isso já é um muro. O que
separa os níveis é o **deslize**: uma chance (50% no Fácil, 15% no Médio, zero no
Difícil) de ele jogar não o melhor lance que achou, mas um dos logo abaixo. É
erro humano, não aleatoriedade — o lance sai da lista ordenada, então nunca vira
palhaçada.

#### Avaliação

Material mais tabelas de casa (*piece-square tables*) no xadrez; material,
avanço e borda nas damas.

As tabelas não são enfeite, e a partida de teste mostrou por quê: sem elas todo
avanço de peão vale exatamente o mesmo — o peão da torre e o do rei saem da
segunda para a quarta linha ganhando idêntico — e a busca desempata pela ordem
da lista. O bot abria com `h4` e mantinha os cavalos em casa. Com as tabelas ele
abre com `Cc3`, desenvolve e roca, sem nenhuma regra de abertura escrita em lugar
nenhum. A tabela da torre trata `a1` e `b1` como iguais de propósito: um empurrão
genérico para o centro fazia a torre ganhar meio ponto indo de `a1` para `b1` e
voltar no lance seguinte — três lances jogados fora para passear com a torre.

Nas damas o avanço pesa bastante porque virar dama é a partida inteira: uma pedra
na sexta linha não é uma pedra, é uma dama atrasada dois lances. E a pedra na
borda ganha um bônus porque ela simplesmente não pode ser capturada — não existe
casa do outro lado para o saltador cair.

#### Detalhes de partida

- O bot começa a pensar **junto com a animação** do lance do jogador; o tempo que
  a peça leva para andar é busca de graça.
- Há um piso de espera de 0,45s antes de ele jogar, mesmo que já tenha decidido.
  Sem ele, o Fácil responde antes de o lance do jogador terminar de pousar, e a
  partida vira um pingue-pongue em que ninguém vê o que aconteceu.
- A **revanche troca as cores**, pelo mesmo motivo da revanche em rede.
- **Sem lance planejado contra o bot**: planejar existe para aproveitar o tempo
  em que o oponente pensa, e o bot pensa por dois segundos.
- O relógio corre normalmente, inclusive para o bot — o tempo que ele gasta
  pensando sai do relógio dele, que é o honesto. E por isso a partida encurta a
  reflexão dele a um vigésimo do que resta: a busca não olha o cronômetro, então
  quem olha por ela é a cena.

### Arrastar a peça

Além de tocar na peça e depois na casa, dá para **arrastar**. Os dois convivem
porque são o mesmo lance: a casa de origem é emitida na descida do dedo, a de
destino na subida, e são exatamente as duas casas que os dois toques emitiriam.
Por isso as regras não sabem que o arrasto existe — `BoardView` continua
emitindo `square_tapped` e mais nada, e a captura encadeada das damas, o roque
pela torre e a promoção seguem funcionando sem uma linha a mais.

Três coisas que não são enfeite:

- **Limiar de 22% da casa** antes de virar arrasto. Dedo nenhum fica parado; sem
  ele, todo toque simples viraria um arrasto de dois pixels.
- **Contorno na casa sob o dedo.** No celular o dedo cobre exatamente a casa em
  que a peça vai cair. Sem o contorno o jogador solta às cegas.
- **Soltar fora do tabuleiro, ou de volta na origem, não é lance** — e a peça
  continua selecionada. Desistir de um arrasto não pode custar a seleção.

O gesto começa no `_gui_input` e termina no `_input`. Não é firula: um arrasto
que sai do tabuleiro deixa de gerar eventos de GUI para o nó, e o gesto ficaria
pendurado, com a peça colada ao último ponto visto e o dedo levantado lá fora
nunca chegando.

O Android manda o toque **e** a emulação de mouse do mesmo dedo por cima. Quem
começou o gesto termina o gesto (`_pointer` guarda "touch" ou "mouse"): sem essa
trava, um arrasto só soltaria o lance duas vezes, e a segunda cairia na casa de
destino selecionando a peça recém-chegada.

### Lance planejado (pré-movimento)

Em partida **em rede**, dá para escolher o lance enquanto o oponente pensa. Ele
sai sozinho no instante em que a vez chega. Num ritmo curto é o que separa um
final jogável de uma corrida de toque.

O plano é guardado como **casas**, não como `Move`: o lance ainda não existe na
posição atual, e só vai existir — ou não — depois que o oponente jogar. Quando a
vez volta, ele é procurado na lista legal **de verdade**, a da posição que o
oponente deixou. Não achou, é descartado com um aviso; acontece o tempo todo e
não é erro, mas sem o aviso o jogador conclui que o toque dele se perdeu no
caminho.

#### Capturas que ainda não existem

O plano é para a posição **depois** do lance do oponente, e três capturas só
existem lá: a **recaptura** (a casa tem peça nossa agora, e é ela que o oponente
vai comer), o **peão na diagonal vazia** (a peça do oponente ainda vai pousar ali)
e a **peça cravada** (o lance dele pode desfazer a cravada). A lista legal de
agora recusava as três, e a recaptura é o pré-movimento mais comum que existe.

Os destinos saem de `ChessRules.premove_candidates`: as outras peças nossas
viram inimigas (capturáveis), as diagonais vazias do peão ganham um alvo, e a
legalidade não é conferida — ela é conferida na hora de jogar, como sempre. Com
a peça erguida, o toque num destino arma o lance **mesmo com peça nossa ali**;
só fora dos destinos o toque em peça nossa troca a peça erguida. É a ordem do
chessground, e o rei erguido também aceita o toque na torre para rocar.

O que continua bloqueando é a peça do oponente no caminho de quem desliza: o
plano não atravessa uma peça que talvez saia.

A espera pela animação do lance do oponente **não sai do relógio**: o tempo é
devolvido antes de o lance sair, porque o pré-movimento existe para custar zero.
E um link que cai nessa espera não apaga a corrente — ela sai quando ele volta.

#### A corrente

Dá para encadear **até quatro** lances. Cada elo é escolhido numa posição
hipotética em que os anteriores já aconteceram — a peça é pega onde ela *vai*
estar, e não onde está —, e sai **um por vez**: o primeiro na vez que chega, o
segundo na seguinte.

São duas hipóteses empilhadas, e as duas são assumidas: que a vez é nossa, e que
o oponente não joga entre um elo e o outro. A segunda é grosseira de propósito —
simular o que ele faria pediria uma busca por elo, e a resposta seria um chute de
qualquer forma. O preço é pago na hora certa: cada elo é revalidado contra a
lista legal de verdade no instante em que sai, e **o primeiro que falhar leva a
corrente inteira junto**. Os elos seguintes foram escolhidos numa posição que
pressupunha o anterior; jogar o segundo sem o primeiro é jogar um lance que
ninguém planejou.

A ordem precisa ser legível, e é a única informação que a marcação sozinha não
carrega: quatro pares de casas azuis não dizem qual sai primeiro. Duas pistas,
as duas contínuas — o elo mais próximo é o mais forte e os seguintes desbotam, e
um **número** na casa de destino diz a posição na fila. O número não desbota
junto: ele é a pista exata, e existe justamente para quando a gradação deixa de
bastar.

Um toque que não continua a corrente apaga **o último elo**, e não a corrente
inteira. Com um lance só os dois são a mesma coisa, que é como era antes;
encadeando, perder quatro decisões por um toque errado seria caro demais.
Cancelar tudo continua possível — são N toques —, e desfazer um engano custa um.

Enquanto o plano espera, o tabuleiro **não mexe**. As casas de cada elo ficam
marcadas em azul, e as peças continuam onde estão: mostrá-las já no destino seria
desenhar uma posição que ainda não existe e que pode nunca existir. O azul é
deliberadamente não-latão — o latão quer dizer "é sua vez, aja aqui", e um plano
é o contrário disso.

Os destinos oferecidos ao escolher vêm de uma cópia do estado com a vez trocada e
com os elos anteriores aplicados (`_premove_state`), passada a
`premove_candidates`. É hipótese, não verdade, e é
por isso que a revalidação existe; mas sem ela planejar seria adivinhar.

Um detalhe que custou um bug: o direito de *en passant* **não** atravessa a troca
de vez. Ele pertence a quem joga na posição real, e na posição real quem joga é o
oponente — então o `ep` que está escrito ali veio do nosso próprio avanço duplo, e
na hipótese descreve um peão nosso. Sem apagá-lo, o peão vizinho ganhava uma
diagonal marcada como **captura** para uma casa por onde o nosso peão tinha
acabado de passar; a revalidação recusava depois, e o jogador não tinha como
entender o que havia sido oferecido.

Sai depois de a animação do lance do oponente terminar. É esse lance que o
jogador está esperando ver, e cortá-lo pela metade esconderia justamente a
informação que motivou o plano.

Qualquer toque que não pegue uma peça nossa cancela o plano — é o gesto que todo
mundo já tenta, e poupa um botão numa tela sem espaço para ele. Promoção
planejada vira dama: é a escolha em quase toda partida, e perguntar ali pararia
o lance para gastar o tempo que o plano existia para economizar.

**Só em rede e só no xadrez.** No mesmo aparelho não existe espera — a vez do
outro é o outro jogador ali do lado, com o mesmo tabuleiro na frente. E nas damas
a captura é obrigatória: o lance do oponente decide qual pedra *tem* de mover,
então quase todo plano nasceria ilegal, e um recurso que falha na maioria das
vezes atrapalha mais do que ajuda. A regra mora em `_premove_allowed()`.

---

## Como rodar

```bash
godot --path . --editor
```

Sem abrir o editor:

```bash
godot --path .
```

Para testar o multiplayer no desktop: abra duas instâncias, uma abre a sala e a
outra entra pelo código. As duas falam com o relay, então funciona igual a dois
celulares — inclusive apontando para um relay local com `CHESS_RELAY_URL`.

### Gerar o APK

Pré-requisitos, uma vez: modelos de exportação Android instalados pelo editor,
Android SDK e JDK **17** apontados em `Editor → Configurações do Editor →
Export → Android`, e um debug keystore no caminho configurado ali (crie com
`keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android
-keystore <caminho> -storepass android -dname "CN=Android Debug,O=Android,C=US"
-validity 9999 -deststoretype pkcs12`).

```bash
godot --headless --path . --export-debug "Android" build/android/cascapp.apk
```

A pasta de destino precisa existir — a Godot não a cria. O preset em
`export_presets.cfg` já traz o rótulo "Cascapp", package `org.cascapp.game`,
arm64, as permissões de rede e NFC, e `tests/*` fora do pacote.

**O package é definitivo.** Para o Android ele **é** a identidade do app: trocá-lo
faz o aparelho tratar o build novo como outro aplicativo — instalação paralela,
preferências e favoritos do anterior fora de alcance — e, na Play Store, uma
ficha nova, sem as avaliações nem a base de instalações da antiga. Ele passou de
`org.jogosderole.game` para `org.cascapp.game` junto com o nome, na 1.17
(código 18) — quem tinha um build anterior instalado fica com os dois lado a
lado, e precisa desinstalar o velho. Daqui em diante o rótulo pode mudar à
vontade; o package, não. O rótulo é o que o
usuário lê; o package é o que o sistema usa.

**Ao subir a versão, mexa só no preset.** `version/name` e `version/code` em
`export_presets.cfg` são o que a loja e o Android leem, e `version/name` é também
o que o rodapé do menu passou a mostrar — o addon `version_stamp` carimba esse
número dentro do build durante a exportação (veja
[Versão do build](#versão-do-build)). `application/config/version` no
`project.godot` ficou como valor de desenvolvimento, para o rodapé dizer alguma
coisa quando se roda pelo editor, onde não existe preset.

Antes os dois tinham de ser bumpados juntos, à mão, e não eram: enquanto isto foi
escrito o preset estava em `1.5` e o `project.godot` em `1.4` — um APK que se
instala como 1.5 e se apresenta como 1.4. É exatamente o número que alguém copia
para relatar um problema.

Atenção: **o editor reescreve `export_presets.cfg` inteiro** ao abrir a janela de
exportação, revertendo o que estiver ali. Se isso acontecer, os campos a
reconferir são `package/unique_name`, `package/name`, as permissões,
`export_path` e `gradle_build/use_gradle_build`.

### Permissões

Quatro permissões, e o app não pede nada ao abrir:

| Permissão | Tipo | Para quê |
| --- | --- | --- |
| `INTERNET` | normal | falar com o relay |
| `ACCESS_NETWORK_STATE` | normal | saber se há rede |
| `NFC` | normal | entregar o código encostando os aparelhos |
| `CAMERA` | **dangerous** | ler o QR |

A câmera é a única com diálogo, e ele aparece quando o jogador toca em "Escanear
QR" — não na abertura.

A lista já foi de oito. Saíram Bluetooth e proximidade de Wi-Fi com o Nearby
Connections; e localização, `CHANGE_WIFI_STATE` e `CHANGE_NETWORK_STATE` com o
hotspot local e a descoberta por UDP. **Nenhuma permissão do app toca em rádio
do aparelho**, e nenhuma é pedida por entrar numa tela.

Pedir permissão que não se usa é o tipo de coisa que faz o jogador desconfiar da
tela de instalação — e a lista é a primeira coisa que ele lê sobre o app.

### APK com os plugins nativos

Os plugins Kotlin de `android_plugin/` já estão compilados e instalados em
`res://android/plugins/`. Para que entrem no APK são necessárias **três** coisas,
e a terceira não está em lugar nenhum da documentação oficial:

1. `gradle_build/use_gradle_build=true` no preset;
2. o template de build extraído em `res://android/build/` (com o marcador
   `res://android/.build_version` contendo `4.7.1.stable.mono`);
3. `plugins/ChessAndCheckersPlugins=true` no preset — a Godot cria um checkbox
   por plugin detectado e ele **nasce desligado**. Sem essa linha o export
   funciona, gera um APK válido e simplesmente não inclui o plugin. Nenhum aviso.

Com `use_gradle_build=true`, o `--export-debug` em headless **não encerra
sozinho**: o APK fica pronto e o processo continua vivo indefinidamente. O sinal
de que acabou é `android/build/build/outputs/` parar de receber escrita, não o
processo terminar — se esperar pelo processo, espera para sempre.

Para reconstruir o `.aar` depois de mexer no Kotlin:

```bash
cd android_plugin && ./gradlew :plugin:assembleRelease
```

e copie `plugin/build/outputs/aar/ChessAndCheckersPlugins.release.aar` para
`res://android/plugins/`.

Cuidado com o export em **Release**: sem keystore de release configurado, o
Gradle cai no debug keystore procurando um alias `android` que não existe lá, e
falha com `No key with alias 'android' found in keystore`. Para testar, use
Debug. Para publicar, crie um keystore próprio e passe as senhas por
`GODOT_ANDROID_KEYSTORE_RELEASE_PATH` / `_USER` / `_PASSWORD` em vez de gravá-las
no `export_presets.cfg`, que é arquivo de projeto.

### Integração contínua

`.github/workflows/ci.yml` roda a cada empurrão em `main` e `develop`, a cada
proposta de junção, e à mão pelo botão do GitHub. São as mesmas linhas de
comando da seção **Testes**, logo abaixo — o CI não tem suíte própria, e isso é
de propósito: um teste que só existe no servidor é um teste que ninguém roda antes de commitar.

Três tarefas:

| Tarefa | O que faz | Quando falha |
|--------|-----------|--------------|
| `relay` | `npm ci`, `typecheck` e `npm test` | o protocolo do servidor quebrou |
| `jogo` | importa o projeto, roda as seis suítes headless e as duas de rede contra um relay de verdade | as regras, as cenas ou o aperto de mão quebraram |
| `apk` | compila o plugin Kotlin, instala o modelo de build e exporta o APK de depuração | o export quebrou, ou o plugin não compila mais |

A importação é tratada como teste: a saída é lida à procura de `SCRIPT ERROR` e
`Parse Error`. Sem isso um erro de sintaxe não derruba nada — a cena não carrega,
o processo não termina, e a tarefa morre no tempo limite meia hora depois.

O APK sai como artefato do trabalho, guardado por sete dias. É **de depuração**:
o de release precisa do keystore, que não está no repositório e não deve estar.
Para publicar, veja a seção de release — as senhas entram por
`GODOT_ANDROID_KEYSTORE_RELEASE_*`, e no CI elas seriam segredos do repositório.

A versão do Godot está escrita uma vez, em `env.GODOT_VERSION`, e tem de
acompanhar o `config/features` do `project.godot`. O download e os modelos de
exportação ficam em cache por versão, em `.github/actions/godot`.

### Deploy dos servidores

`.github/workflows/deploy.yml` publica os **dois** servidores no Fly: o relay
(Node, `relay/`) e o de Bomberman (o mesmo projeto Godot, sem tela). São dois
apps porque são dois bichos — um repassa bytes de jogos por turno, o outro roda
uma simulação a 30 Hz por sala e fala UDP.

Ela dispara em `main`, e só quando muda algo que de fato afeta um deles. O filtro
não é economia: o servidor de Bomberman é o projeto Godot inteiro rodando sem
tela, então quase toda mudança de **regra** o afeta — mas uma mudança de tela,
não. Sem o filtro, cada ajuste de cor num cartão de menu reconstruiria uma imagem
de Godot e reiniciaria as partidas em curso. É a separação entre `core/` e `ui/`
virando regra de esteira.

Um segredo, `FLY_API_TOKEN`, com acesso aos dois apps. Sem ele a tarefa falha
**dizendo isso**, em vez de morrer dentro do `flyctl` com uma mensagem de
autenticação que não explica o que fazer.

Os dois terminam com `fly scale count 1`, e ele não é economia de custo: as salas
— e, no Bomberman, a partida inteira — moram na memória do processo. É a
armadilha das limitações conhecidas, transformada num passo que roda sozinho.
Depois disso o relay é conferido pelo `/healthz`: o que decide se a publicação
deu certo é o processo **respondendo**, e não o código de saída do `deploy`.

### Release por tag

`.github/workflows/release.yml` publica um APK **assinado** a partir de uma tag:

```bash
git tag v1.16 && git push origin v1.16
```

A esteira roda as suítes de novo, confere que a tag e o `version/name` do
`export_presets.cfg` dizem o mesmo número, exporta em release, verifica a
assinatura com o `apksigner` e cria a release no GitHub com o APK anexado.

A conferência de versão existe porque este projeto já errou isso: o preset em
1.5 e o `project.godot` em 1.4, um APK que se instala com um número e se
apresenta com outro. `version/name` é a fonte única — o addon `version_stamp`
carimba esse valor dentro do pacote —, e uma tag que discorda dele produz uma
release cujo número ninguém consegue citar sem errar.

Disparada à mão pelo botão do GitHub, a esteira faz tudo menos publicar: o APK
sai como artefato do trabalho. É o caminho para testar a assinatura sem queimar
uma tag.

#### Os três segredos

O keystore não está no repositório e não deve estar. Ele vive como segredo, em
base64, e no runner é escrito em `$RUNNER_TEMP` — fora da área de trabalho, onde
não há como acabar num artefato ou num commit — com permissão `600`, e apagado
no fim mesmo quando o export falha.

| Segredo | O que é |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | o `.jks` inteiro, em base64 |
| `ANDROID_KEYSTORE_ALIAS` | o alias da chave dentro do keystore |
| `ANDROID_KEYSTORE_PASSWORD` | a senha do keystore e da chave |

Para gerar o base64 e descobrir o alias:

```bash
base64 -w0 release-keystore.jks > keystore.b64
```

```bash
keytool -list -v -keystore release-keystore.jks | grep -i "Alias name"
```

Os três entram em **Settings › Secrets and variables › Actions › New repository
secret**, no GitHub. Apague o `keystore.b64` depois de colar — ele é o keystore
inteiro em texto.

O Godot lê os três por variável de ambiente
(`GODOT_ANDROID_KEYSTORE_RELEASE_PATH` / `_USER` / `_PASSWORD`) em vez de pelo
`export_presets.cfg`, que é arquivo de projeto e vai versionado.

### Testes

```bash
godot --headless --path . --import
godot --headless --path . --script res://tests/test_runner.gd
godot --headless --path . res://tests/scene_probe.tscn
godot --headless --path . res://tests/pairing_probe.tscn
godot --headless --path . res://tests/ludo_probe.tscn
godot --headless --path . --script res://tests/monopoly_probe.gd
godot --headless --path . --script res://tests/bomber_probe.gd
```

O relay tem suíte própria, em Node:

```bash
cd relay && npm install && npm test
```

E o caminho pela internet, ponta a ponta contra um relay de verdade:

```bash
cd relay && npm start
```

```bash
CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/relay_smoke.gd
```

```bash
CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/table_smoke.gd
```

```bash
CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/ludo_net_smoke.gd
```

```bash
CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/ludo_bots_smoke.gd
```

```bash
CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/monopoly_net_smoke.gd
```

```bash
CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/rejoin_smoke.gd
```

```bash
CHESS_RELAY_URL=ws://127.0.0.1:8080/ws godot --headless --path . --script res://tests/bomber_net_smoke.gd
```

`test_runner.gd` cobre o que é fácil de errar sem perceber: `perft` do xadrez nas
profundidades 1–3 (20 / 400 / 8902 posições), roque, promoção e um mate de teste;
a lei da maioria e a promoção nas damas; a estrutura da matriz do QR Code,
incluindo a informação de formato conferida contra a tabela publicada na norma; e
o round-trip do payload de pareamento.

`relay_smoke.gd` sobe os dois lados no mesmo processo, cada um com seu
`RelayBridge`, e os faz se acharem pelo código da sala num relay rodando de
verdade: aperto de mão, cores, transporte de lance com índice, relógios e
resync. Também cobre a **recusa** — entra numa sala que ninguém abriu e exige o
motivo certo em menos de 10 segundos, que é a regressão do bug em que o cliente
descartava a resposta do servidor e entrava em reconexão por 90s.

`table_smoke.gd` cobre a camada abaixo dele: uma **mesa de quatro**, com quatro
`RelayBridge` no mesmo processo. O que uma sala de dois nunca exercitou — cada um
num assento, a mesa só ficando pronta no quarto, um lance saindo para os outros
três assinado por quem jogou, e quem cai voltando para o **mesmo** assento
mesmo havendo outro livre antes dele.

`rejoin_smoke.gd` é o aperto de mão de quem **volta**, que é outro que o de quem
chega: numa mesa de Uno de quatro, dois caem sem avisar e viram bot na hora; o
assento 3 volta **antes** do 2 com a chave e recebe o 3, com a semente da partida
em curso; depois o anfitrião cai, o assento 1 passa a jogar pelas máquinas, e o
anfitrião volta sem abrir partida nova nem mexer na semente dos outros. Por fim
uma mesa de dois, onde o anfitrião que caiu é recebido pelo convidado e volta com
as próprias peças e o ritmo da partida.

`ludo_net_smoke.gd` fecha a pilha: quatro `net_link.gd` numa mesa de Ludo. Prova
que ninguém começa a jogar com três na sala, que cada assento vira uma cor, e
que um lance com dado dentro faz os **quatro** tabuleiros derivarem a mesma
posição — que é a razão de o dado morar dentro do `Move`.

`ludo_bots_smoke.gd` cobre a sala que não enche: dois humanos numa mesa de
quatro, os outros dois lugares virando máquina, e os dois aparelhos concordando
sobre **quais** cores são de bot. Sem esse acordo, um dos lados esperaria para
sempre uma vez que ninguém ia jogar.

`monopoly_net_smoke.gd` cobre o que Metrópole trouxe em cima disso, mais as duas
garantias de mesa grande: que todo lance recebido chega **com o assento de quem o
mandou**, e que um jogador fechando o app numa mesa de quatro não acaba a partida
dos outros três — a cadeira vira máquina, os três seguem conectados, e quem joga
pelas máquinas passa a ser o menor assento humano que sobrou.

Cobre também o **formato** da partida chegando aos quatro pelo `welcome`, e uma
**troca** atravessando a rede. A troca é o único lance de tamanho variável do jogo e o único que o outro
lado não confere pertencendo a `generate_moves` — se os dois lados lessem o
caminho `[OFFER, …]` de formas diferentes, as escrituras mudariam de mão de forma
diferente em cada aparelho. E é a única fase em que quem manda o lance seguinte é
o aparelho de **quem não está jogando**.

`ludo_probe.gd` (headless, sem relay) joga uma partida inteira entre quatro bots
com semente fixa: prova que ela termina, que a heurística sempre tem o que
responder — um `null` numa rolagem sem lance possível trava a vez, e só apareceria
depois de dezenas de jogadas com quatro pessoas esperando — e que repetir o
histórico devolve a mesma posição.

Sem `CHESS_RELAY_URL` nenhum dos quatro de rede roda — apontar um teste
automatizado para o relay de produção abriria salas de verdade a cada execução
da suíte.

Para olhar a tela de Metrópole sem depender do aparelho:

```bash
godot --path . --resolution 1280x720 res://tests/monopoly_sheet.tscn
```

Ele arma uma posição de **vitrine** — um exemplar de cada coisa que o tabuleiro
sabe desenhar: grupo fechado com casas, grupo com hotel, propriedade hipotecada,
aeroporto e companhia com dono, dois peões dividindo a mesma casa, e alguém
preso. Uma posição sorteada mostraria o caso comum, que é o tabuleiro quase
vazio, e é justamente onde não há nada para julgar.

São quatro prints, um por lado: é o giro de câmera visto parado. Se algum deles
sair com a fileira **de baixo** de cabeça para baixo, o giro está errado — e essa
é a coisa que o 3D existe para resolver.

O quinto é **solo**: as três cadeiras que não são a sua viram máquina e a vez do
bot começa sozinha.

Depois vêm as duas telas que cobrem tudo: a **mesa de troca** aberta com as duas
colunas cheias, e o **fim por rodadas** com a tabela de patrimônio. As duas são
as que mais dependem de caber, porque não têm rolagem para esconder o excesso.

E o último enquadra o **tabuleiro inteiro**, que a partida nunca mostra — a
câmera segue o peão da vez de perto, e o miolo aparece só de raspão. É o print
que julga o desenho do tampo, que é outra coisa do que julgar o enquadramento.

O quarto **joga um turno de verdade**: aperta "Rolar", espera os dados pararem, a
pausa de leitura passar, e fotografa com o peão no meio do caminho. É o único que
prova que o ciclo anda; os outros três provam só que a tela desenha.

A espera é contada em **segundos**, não em quadros. O ciclo é cronometrado — 0,95s
de dado, 0,5s de leitura, 0,085s por casa — e contar quadros amarra a foto à taxa
de atualização da máquina: numa placa rápida, 160 quadros passavam antes de o peão
sair do lugar, e o print saía com o tabuleiro parado parecendo um jogo travado.

`monopoly_probe.gd` (headless, sem relay) cobre os três lugares onde este jogo
erra em silêncio. A **máquina de fases**: uma partida inteira jogada ao acaso com
semente fixa, cinco sementes, provando que nenhuma sequência de fases chega a uma
lista de lances vazia com a partida em andamento — que é como um turno trava com
seis pessoas esperando. O **replay**: repetir `history` tem de devolver `meta`
idêntico, chave por chave, porque é literalmente o que a reconexão faz. E a
**independência da cópia**, que é o teste que achou um bug de verdade no núcleo
compartilhado (veja [Erros que valem registro](#erros-que-valem-registro)).

Cobre também a **geometria do anel**: que as 40 casas cobrem a moldura exatamente
— sem fresta nem sobreposição —, que casas consecutivas se tocam, que só os
quatro cantos são quadrados e que o "dentro" de cada casa aponta mesmo para o
miolo. Um erro de meia unidade aqui não trava nada; deixa uma fresta preta entre
duas casas que ninguém vê num print e todo mundo vê no aparelho.

Cobre ainda o **caminho da caminhada** — que a volta pela frente atravessa a
Partida em vez de voltar por trás, que só a carta de recuar recua, e que de
qualquer casa para qualquer outra, nos dois sentidos, o caminho chega sem dar a
volta inteira — e as **partidas entre bots**: três sementes fixas provando que a
heurística sempre responde, que a resposta está na lista de lances legais, e que
a partida termina. Um `null` numa fase qualquer trava a vez de um bot, e com
quatro cadeiras de máquina isso trava tudo; jogando, só apareceria depois de
dezenas de turnos.

E a **troca**, que precisa de teste próprio porque é o único lance cuja
legalidade não é conferida por pertencer a uma lista: toda a proteção mora no
predicado do `validate`, e o que não estiver coberto ali não está coberto em
lugar nenhum. O que se testa é o que um cliente modificado tentaria — dar o que
não é seu, pedir o que o outro não tem, pagar dinheiro que não existe, oferecer a
mesma casa duas vezes, propor no meio de um momento em que a partida já está
esperando outra resposta —, mais o que a troca faz quando aceita: as escrituras
mudando de mão com a hipoteca junto, a recusa devolvendo a fase intacta, e a
dívida sendo quitada por uma troca fechada na fase RAISE. Em rede isso não é
hipótese: é a única barreira entre o outro aparelho e o tabuleiro daqui.

`bomber_probe.gd` (headless, sem relay) tem o **determinismo** como teste que
sustenta todos os outros. Bomberman é o primeiro jogo do app em que os aparelhos
não trocam posições: cada um roda a mesma simulação com os mesmos comandos e
confia que chegou ao mesmo lugar. A suíte confere o estado inteiro depois de
centenas de tiques, e não só o que cada regra faz isoladamente — porque uma
divergência de uma unidade não aparece como erro, aparece como um jogador vivo
numa tela e morto na outra, vinte segundos depois.

Cobre também o **acerto de passo** (`core/bomber_lockstep.gd`): que o comando
vale com atraso e não na hora, que a mensagem só sai a cada três, que o repetido
não sobrescreve o que já chegou, e que um tique sem o byte de alguém **não roda**
— parar é a única resposta que converge, porque prever ou repetir o último comando
faz dois aparelhos discordarem sobre o passado. Mais a **saída de cadeira**, que
sai num tique anunciado com o histórico dela junto: sem o repasse, quem ficou sem
os últimos bytes de quem caiu esperaria por eles para sempre.

E fecha com **dois aparelhos** no mesmo processo, cada um com o seu acerto de
passo, trocando comandos por um correio que atrasa quatro tiques e perde uma
mensagem inteira. Os dois param em tiques diferentes — é o ponto — e terminam com
o mesmo mapa, os mesmos bonecos e o gerador no mesmo ponto.

`bomber_net_smoke.gd` põe isso na rede de verdade, que é o que aquele não pode
fazer: que a **semente viaja** no `welcome` (dois mapas diferentes aparecem como
um jogador atravessando uma parede que só existe na tela do outro), que o comando
sobrevive à ida e volta pelo JSON, e que as duas simulações convergem. Ele anda no
relógio de verdade de propósito: o relay corta a sessão de quem passa de quarenta
mensagens por segundo, e a primeira versão deste teste — que bombardeava um
`_pump` por quadro — acusava dessincronia onde havia desconexão.

`pairing_probe.gd` abre as duas telas de menu e a de pareamento nos dois papéis,
com os autoloads de verdade: a escolha do jogo (um cartão por entrada do
catálogo, tocar grava o jogo), o painel de ajustes (abre em criar/local, não em
entrar; a escolha de ritmo grava mesmo) e os três caminhos de pareamento. Existe por causa
da primeira rodada de testes em aparelho, onde a tela abria, o QR aparecia e
nenhum caminho conectava — as duas causas eram silenciosas (veja [Erros que
valem registro](#erros-que-valem-registro)).

`npm test` no relay cobre o registro de salas (reconexão que reocupa o assento,
sala cheia, carência antes de apagar) e o servidor ponta a ponta com sockets de
verdade em porta efêmera.

Para conferir o QR com uma câmera de verdade:

```bash
godot --headless --path . --script res://tests/dump_qr.gd
```

Ele salva um PNG em `user://qr_sample.png` e imprime o caminho absoluto.

---

## Estrutura

```
core/                 regras e estado, sem nenhuma dependência de UI ou de rede
  board.gd            codificação de casas e peças (1 int por casa)
  match_state.gd      posição completa + metadados por regra
  move.gd             um lance (caminho, capturas, promoção)
  ruleset.gd          interface implementada por todos os jogos
  chess_rules.gd
  checkers_rules.gd
  battleship_rules.gd resolução dos tiros e posicionamento da frota
  ludo_rules.gd       percurso, dado dentro do lance e captura na trilha
  monopoly_board.gd   as 40 casas, os grupos e as tabelas de aluguel
  monopoly_rules.gd   o turno em fases, a troca por predicado e a falência
  uno_rules.gd        baralho semeado, pilha de compra, grito e dúvida
  pool_rules.gd       a mesa, a física determinística e os dois formatos
  bomber_rules.gd     a simulação de passo fixo, sem tela e sem rede
  bot.gd              busca alfa-beta, sem saber qual jogo está jogando

net/
  relay_bridge.gd      WebSocket para o relay: sala, keepalive e reconexão
  qr_encoder.gd        codificador QR completo em GDScript (byte mode, nível M)
  qr_code_view.gd      Control que desenha o QR
  nfc_bridge.gd        ponte para o singleton Android GodotNfc (opcional)
  qr_scanner_bridge.gd ponte para o singleton GodotQrScanner (opcional)

addons/
  version_stamp/       carimba version/name do preset dentro do build

autoload/
  game_state.gd       "Game" — catálogo de jogos e escolhas do menu
  net_link.gd         "Net"  — handshake e protocolo sobre a sala
  pairing.gd          "Pairing" — código, payload e as pontes de NFC/QR
  prefs.gd            "Prefs" — nome, som, favoritos, em user://prefs.cfg

scenes/
  main_menu.tscn/.gd  grade de jogos: favoritos, categorias, gaveta
  game_menu.tscn/.gd  como jogar o jogo escolhido, + painel de ajustes
  pairing.tscn/.gd    abrir sala: código, QR e cartão NFC emulado
  join.tscn/.gd       entrar numa sala (hospeda ui/join_panel.tscn)
  settings.tscn/.gd   nome, som e vibração, e o que este build consegue fazer
  match.tscn/.gd      fluxo da partida de xadrez e damas, reconexão e resync
  battleship_match.tscn/.gd  posicionamento, dois mares e tiro
  ludo_match.tscn/.gd  o ciclo role-e-escolha, com quatro cores num aparelho
  monopoly_match.tscn/.gd  o turno em fases, a coluna de jogadores e o 3D
  uno_match.tscn/.gd   a mesa, a mão em leque e os botões de lance sem carta
  bomber_match.tscn/.gd  o relógio de passo fixo e os dois controles de polegar
  pool_match.tscn/.gd  a mesa, o arrasto que vira tacada e a tacada assistida
  board_view.gd       desenho do tabuleiro e das peças (herda GridView)
  piece_renderer.gd   ponto único de desenho de peça (textura, ou polígono)

ui/                   tema, cartões de jogador (com relógio), banner, último lance
  grid_view.gd        grade 8x8: moldura, coordenadas, geometria e gesto
  waters_view.gd      um mar da batalha naval, com a névoa
  join_panel.tscn/.gd os quatro caminhos até uma sala: lista, código, QR, NFC
  chip_bar.gd         fileira de filtros (categorias na home, jogos no multiplayer)
  app_bar.gd          barra superior: gaveta ou volta, título, ação
  nav_drawer.gd       gaveta: início, multiplayer, configurações
  icon_button.gd      botão redondo com o ícone desenhado em traço
  switch_row.gd       linha de ajuste com interruptor
  ludo_view.gd        a cruz 15x15, os currais e os dezesseis peões
  die_view.gd         o dado: face, giro e o toque que pede um número
assets/pieces/        21 SVGs: 12 de xadrez, 4 de damas, a âncora e 3 de casco

relay/                servidor de salas em TypeScript (Node + ws), com testes
android_plugin/       plugins Kotlin opcionais (NFC e leitura de QR)
tests/                test_runner.gd, relay_smoke.gd, table_smoke.gd, probes
```

### Interface

A interface é o tema **Boteco**: uma mesa de bar vista de cima. Lousa verde-escura
no fundo, giz nos textos e contornos, uma placa amarela para a ação da tela e
papel para as três coisas que são papel de verdade — a comanda com o código da
sala, a escritura de Metrópole e o fim de partida. O desenho e as decisões estão
em [docs/superpowers/specs/2026-09-16-redesenho-boteco-design.md](docs/superpowers/specs/2026-09-16-redesenho-boteco-design.md);
o plano, etapa a etapa, em [docs/superpowers/plans/2026-09-16-redesenho-boteco.md](docs/superpowers/plans/2026-09-16-redesenho-boteco.md).

O tema continua construído em código ([ui/app_theme.gd](ui/app_theme.gd)) e
aplicado na raiz de cada cena. As fontes são embarcadas, todas OFL, em
`assets/fonts/`: **Big Shoulders** no letreiro (títulos e botões),
**Atkinson Hyperlegible** no texto que precisa ser lido longe do rosto, e **IBM
Plex Mono** nos números que precisam alinhar — relógio, dinheiro, código da sala.
`SystemFont` saiu porque nenhuma dessas três vozes existe garantida num aparelho.

#### Os objetos do tema

| Objeto | Componente | Onde aparece |
|--------|------------|--------------|
| Bolacha de chopp | `Coaster` | avatar do jogador, ícone do jogo, `?` da barra, direcional do Bomberman |
| Papel | `PaperCard` | comanda do código, escritura, fim de partida, boas-vindas |
| Giz tracejado | `StyleBoxDashed` | botão secundário, etiqueta de quem espera, aviso |
| Placa | `AppTheme.plate()` | a ação da tela — uma por tela, no máximo |
| Abas de escolha | `SegmentedControl` | modo na folha do jogo, formato nas regras |

Os botões seguem dois eixos, e cada um responde uma pergunta. **Peso** (quanta
atenção o botão pede): placa → contorno → tracejado. **Cor** (o que ele faz):
amarelo é a ação da tela, verde é confirmar e começar, vermelho é desistir e
sair. Um destaque novo é uma combinação dos dois, nunca uma cor nova.

#### Navegação

Três abas na base — **Jogos · Online · Você** —, no lugar da gaveta e da
engrenagem. Jogos é o cardápio: os favoritos em cima e o catálogo como lista de
lousa, com a peça numa bolacha, o nome, o pontilhado e a lotação. Tocar num jogo
abre a **folha do jogo** (`GameSheet`), que junta numa camada só o que eram duas
telas: o modo em abas, os ajustes daquele modo, um botão para começar e o link
"Como jogar". Online é a aba de entrar numa sala — o código em seis casas de
papel, o QR, o NFC e a lista de salas abertas — e de criar uma. Você é o nome e a
bolacha com que o jogador aparece na mesa.

A sala de espera de quem abre (`scenes/pairing.tscn`, e a do Bomberman) mostra o
código numa comanda com "Copiar" e "Mostrar QR" — o QR começa escondido, porque
ocupa meia tela para servir a um caminho só — e as cadeiras em volta da mesa, com
quem já sentou.

#### A partida

Toda partida tem a mesma moldura: a **barra da partida** (`MatchBar`) no topo, com
sair, o nome do jogo, tempo, rodadas e código da sala, o `?` das regras desta
mesa e as ações do jogo. Na Metrópole ela é translúcida, por cima do tabuleiro 3D.
Cada jogador é uma **etiqueta** (`PlayerTag`): a faixa larga nas telas em pé, com
capturas e relógio num placar, e a etiqueta curta nas deitadas, presa ao lugar do
dono — ao leque de cada assento no Uno, ao canto de cada cor no Ludo.

Sair pergunta antes, pelo botão ou pelo gesto de voltar do Android. Com o fim de
partida na tela, o gesto sai direto: não há mais partida a proteger.

#### Como jogar

As regras dos oito jogos moram em `data/rules/<id>.tres`, um `GameRulesDoc` por
jogo — objetivo, passos numerados e avisos, e um bloco por formato na sinuca. Elas
foram escritas a partir do código de regras, e quem mudar uma regra em `core/`
muda a frase ali junto. Duas portas levam a elas: o link da folha do jogo abre a
página inteira (`RulesPage`); o `?` da barra abre a gaveta **Regras desta mesa**
(`TableRulesDrawer`), com o que vale nesta partida e o estado de cada regra — o
0 e o 7 do Uno, o formato da sinuca, o limite de Metrópole. A gaveta é uma função
pura das opções ([ui/rules/table_rules.gd](ui/rules/table_rules.gd)), com os números
lidos das constantes das regras.

#### O que o redesenho não tocou

O logo, as peças de xadrez, damas e Ludo, os barcos da batalha naval, o tabuleiro
de Metrópole e as cartas de Uno são desenho protegido: não mudaram um pixel. Tudo
o que eles liam do tema — fonte, fundo, cores de estado — foi congelado em
constantes antes da troca de paleta, e a prova é por imagem:
[tests/image_diff.gd](tests/image_diff.gd) compara as folhas de referência de
antes do redesenho com as de agora, e a resposta aceitável é "iguais". O
tabuleiro de Metrópole é comparado por região, porque o fundo da sala em volta
dele segue o tema de propósito.

#### Ajustes, e o nome do jogador

A aba Você (`scenes/settings.tscn`) é o nome, a bolacha com que o jogador aparece
na mesa, e os interruptores de som e vibração. O nome precisa de um lugar óbvio,
e óbvio é uma aba na base, não um campo escondido dentro de outra coisa.

`Prefs` guarda em `user://prefs.cfg` (o `res://` é o pacote do app, somente
leitura no Android) e é **estático, não autoload**: um autoload é um nó vivo na
árvore a partida inteira, e isto é um arquivo lido uma vez e escrito quando
alguém muda de ideia.

O campo fica **vazio** enquanto ninguém escolheu, com "Você" só no placeholder:
um padrão dentro do campo parece nome digitado, e ninguém troca o que já parece
escolhido. `Prefs.player_name()` devolve "Você" nesse caso, então o cartão de
jogador não precisa saber a diferença. Salvar espaço em branco apaga o nome — é
o que quem limpou o campo quis dizer.

#### Entrar não passa pela escolha do jogo

Escolher o jogo é o caminho de **abrir** partida, e só. Entrar numa que já existe
tem tela própria (`scenes/join.tscn`), que é a aba Online.

A assimetria é o ponto: quem abre decide o jogo e o ritmo; quem entra recebe os
dois no aperto de mão. Antes as duas ações moravam juntas na tela de como jogar,
e "Entrar em uma partida" obrigava a responder "xadrez ou damas?" antes de
mostrar a lista — uma pergunta cuja resposta era descartada logo depois, e que
levava o jogador a uma lista onde a única sala aberta era do outro jogo.

Os quatro caminhos até uma sala — lista de salas abertas, código de 6
caracteres, QR e NFC — são um componente só (`ui/join_panel.tscn`), e não uma
metade da tela de pareamento. A tela que o hospeda cuida do que só ela sabe:
título, volta, toast dos erros e para onde ir quando o anfitrião responde.

Dentro dele os caminhos ficam separados por **quem já sabe o que quer**: código,
QR e NFC vivem num cartão no topo, porque os três são a mesma coisa — alguém
passou o nome da sala —, e a lista embaixo é para quem veio procurar. O código
vem antes da lista também porque é o único caminho que funciona com sala
privada; a lista só mostra as públicas.

O **NFC escuta o tempo todo** enquanto a tela está aberta. Era um botão
"Encostar (NFC)": tocar nele não produzia nada visível, e o gesto que a
tecnologia pede já é encostar — o botão era um passo a mais para dizer o que uma
frase diz melhor. A câmera continua atrás de um toque, e a assimetria é
deliberada: ler NFC não acende hardware nem pede permissão em tempo de execução,
e a câmera faz as duas coisas.

O campo do código é maiúsculo **na tela**, não só no envio. Converter só na hora
de mandar consertava a requisição e não a confusão: o jogador lia `d3f9k1` na
tela, recebia "sala não encontrada" e conferia caractere por caractere um código
que estava certo.

O rodapé mostra a versão junto das capacidades (`v1.5 • On-line: sim • NFC:
não`), porque as duas respondem a mesma pergunta: que build é este e o que ele
faz.

#### Versão do build

**A versão vem do preset de exportação, carimbada dentro do build.** O addon
`addons/version_stamp/` implementa um `EditorExportPlugin` que, em
`_export_begin`, lê `version/name` do preset e grava `res://version.gen.txt` no
pacote. [ui/app_version.gd](ui/app_version.gd) lê esse arquivo, e cai em
`application/config/version` do `project.godot` quando ele não existe — que é o
caso de toda execução pelo editor.

Isso existe porque `export_presets.cfg` **não vai junto no APK**: é arquivo de
editor, e ler o preset em tempo de execução não é opção. O número precisa ser
carimbado no momento em que a exportação acontece.

O carimbo sai no log da exportação (`VersionStamp: v1.5`) de propósito: é a única
confirmação de que o número certo entrou, e ela aparece antes de o Gradle demorar
alguns minutos para descobrir que estava errado.

Preset sem `version/name` preenchido carimba string vazia, e o leitor trata isso
como ausência — senão o rodapé mostraria um "v" sozinho.

De quem é a vez virou **posição, não texto**: dois cartões
([ui/player_card.gd](ui/player_card.gd)), um aceso e outro apagado, com a peça do
lado como avatar. Em rede o cartão de baixo é sempre o do jogador local, então
"embaixo sou eu" nunca muda de significado.

A diferença entre aceso e apagado é somada em quatro sinais, e não confiada a
um: borda de 2px em latão cheio, um brilho da mesma cor em volta, o fundo
levemente aquecido, e o cartão parado recuando também no conteúdo (avatar a 45%,
nome a 50%). A primeira versão tinha só uma borda de 1px a 55% de opacidade e
sumia no fundo escuro.

Vale o princípio: a leitura é **relativa**. Realçar só o lado aceso resolve pela
metade — afastar os dois extremos dobra a diferença pelo mesmo custo visual, e é
o que faz a resposta chegar de relance em vez de por comparação.

As peças capturadas ficam **dentro** do cartão, na linha de baixo, ordenadas do
peão para a dama, com o `+N` de vantagem só do lado que está na frente. A
primeira versão era uma faixa própria acima e abaixo do tabuleiro; ela custava
~70px de altura, que num celular em retrato saem direto do tabuleiro, e uma
fileira de peças flutuando fora do cartão não dizia de quem era. Dentro do
cartão o espaço já existia — entre o nome e a etiqueta do canto era quase tudo
vazio — e a autoria fica óbvia.

O último lance é uma linha sobre o tabuleiro
([ui/last_move.gd](ui/last_move.gd)): a peça que se moveu, na cor de quem jogou,
o nome do lado e a notação. O "quem" é respondido por imagem antes da leitura. A
linha é centralizada como bloco para não dançar de um lado ao outro a cada
lance — o olho volta sempre ao mesmo ponto.

A escolha de ritmo usa a variação `ChipSelected`: contorno e texto em latão, sem
preenchimento. O latão sólido é reservado para a ação principal da tela, que é
uma só — duas competiriam e o olho iria para a errada.

O xeque aparece em três canais, cada um com um papel: o cartão fica vermelho
(estado contínuo), o rei pulsa no tabuleiro (localização) e um banner anuncia uma
única vez (o instante em que mudou). O banner é transitório de propósito —
permanente, cobriria a fileira de trás justamente quando ela mais importa.

### Aviso: toast, não rodapé nem modal

O mesmo [ui/banner.gd](ui/banner.gd) atende as duas telas. Erros de pareamento —
código com tamanho errado, QR de outro app, nenhuma partida encontrada — iam
para a linha de status do rodapé, e morriam lá: aquela linha muda a cada
endereço tentado ("conectando a 192.168.0.4… (1 de 3)"), então o olho aprende a
ignorá-la. Agora sobem como toast no topo.

Toast e não modal: um modal cobraria confirmação de cada aviso, inclusive dos
que o jogador entendeu antes de terminar de ler. O toast some sozinho, e o tempo
que fica na tela **acompanha o tamanho do texto** — uma frase de duas linhas não
pode durar o mesmo que "Xeque!".

O que continua no rodapé é o progresso, que acontece sozinho e não pede reação.

Duas coisas que a mudança exigiu do componente: **quebra de linha por palavra**,
porque as frases de pareamento são longas e antes vazavam pelos dois lados da
tela; e a caixa **encostada no topo** do nó em vez de centralizada nele, para
uma mensagem de três linhas crescer para baixo em vez de subir por cima do que
está acima dela.

Cinco armadilhas que custaram tempo e valem estar escritas:

- **`Container` zera `rotation` e `scale` dos filhos.** `fit_child_in_rect`
  aplica posição e tamanho e, junto, redefine as duas — então girar um filho
  direto de `VBoxContainer` não sobrevive ao primeiro layout, sem erro nenhum. O
  modo mesa resolve com um `Control` liso no meio: o filho *dele* não é
  gerenciado por container e mantém a rotação. Foi por isso que o cartão do
  oponente continuava em pé mesmo com `upside_down = true`.
- **`draw_set_transform` substitui, não compõe.** Por isso a meia volta é do nó
  e não de dentro do `_draw`: `PieceRenderer` chama `draw_set_transform` por
  conta própria para desenhar a peça, e sobrescreveria a transformada do cartão
  — a peça sairia direita num cartão de ponta-cabeça.
- **`modulate` no nó raiz não agrupa a cena.** As telas entram com um fade de
  0,16s, e `modulate.a` é aplicado a *cada* filho separadamente, não ao conjunto
  — no meio do fade um painel opaco deixa ver o que está atrás dele. Um print
  tirado cedo demais documenta um bug de transparência que não existe (foi o que
  aconteceu com o painel de lances; a correção foi no gerador de prints, não na
  cena).
- **`Window.theme` não desce para os Controls.** Aplicar o tema em
  `get_tree().root` não resolve nem o tipo base: tudo continua com a aparência
  padrão da engine, sem erro nenhum. O tema entra pela raiz de cada cena.
- **`SystemFont` precisa ser cacheado.** Criar um por chamada de `draw_string` —
  isto é, por quadro — desenha blocos em vez de texto, porque a fonte nunca chega
  a carregar os glifos.
- **Modo *edge to edge* exige área segura.** O app desenha sob o notch e a barra
  de navegação; [ui/safe_area_margin.gd](ui/safe_area_margin.gd) mantém o fundo
  até a borda e recua só o conteúdo, convertendo pixel de tela para pixel de UI
  (o projeto usa `stretch/canvas_items`, então os dois não são a mesma coisa).

Três ferramentas renderizam fora do editor, para julgar mudança visual sem
passar pelo aparelho — foi assim que os itens acima apareceram:

```bash
godot --path . --resolution 720x1280 res://tests/screen_sheet.tscn
godot --path . --resolution 720x1280 res://tests/piece_sheet.tscn
godot --path . res://tests/card_art.tscn
```

A primeira salva as telas em `user://shots/`; a segunda salva em
`user://pieces.png` uma folha de contato com todas as peças, nas duas cores, em
tamanho grande e no tamanho real de tabuleiro em celular. A folha de contato é o
que responde se um asset novo aguenta o tamanho pequeno — no tabuleiro quase
tudo parece bom.

A terceira **gera asset**, e não print: `assets/cards/<jogo>.png`, o tabuleiro
desfocado que aparece atrás de cada linha do menu inicial. Ela renderiza o
próprio `BoardView`/`WatersView` do jogo, então a arte acompanha a paleta e as
peças em vez de divergir delas na primeira mudança; o desfoque, os cantos
arredondados e o degradê que apaga a arte do lado do texto ficam assados no PNG,
e o cartão só desenha a textura. Rodar de novo depois de mexer em peça ou cor de
casa, e reimportar (`godot --headless --path . --import`). Nenhuma das três roda
com `--headless`: sem servidor de vídeo o viewport sai preto.

`07_material` existe só como caso de layout: planta oito capturas de um lado
para ver o cartão cheio disputando a linha com o relógio — chegar nesse estado
jogando levaria 40 lances. `08_ajustes` abre o painel de ritmo, e `09_revanche`
mostra o painel de fim de partida no estado mais cheio, com aceitar e recusar
convite — é o caso que responde se três botões ainda cabem. As telas de
partida saem com o ritmo 3 + 2, porque um print sem relógio não mostra o layout
que precisa ser julgado.

### Os nomes na mesa

Cada aparelho sabia só o **próprio** nome. Todos os outros eram "Oponente" ou
"Jogador 3" — numa mesa de seis, cinco desconhecidos numerados. O `prefs.gd` já
anotava a lacuna: "é a primeira coisa que um dia viaja no aperto de mão".

Quem anuncia é cada um, e o anúncio pega carona no aperto de mão que já existia:
quem abre manda a lista no `welcome`, quem entra devolve o próprio nome no
`ready`. Como o relay entrega a mensagem a **todos** os presentes, o `ready` de
um convidado também chega aos outros convidados — o anfitrião não precisa
repassar nada. O `resume` leva a lista de novo, que é o que cobre quem reabriu o
app e perdeu o que tinha aprendido.

O assento vem do **servidor**, não da mensagem. O convidado manda um campo
`seat` para a contagem do aperto de mão, mas guardar o nome por ele deixaria
qualquer um renomear o vizinho.

Nome é **enfeite**, e é por isso que ele pode viajar por fora do histórico de
lances: se um se perder, a partida continua idêntica e o cartão volta a dizer
"Jogador 3". Nada do que decide a partida anda por esse canal.

O que chega é texto escolhido por outra pessoa e desenhado na nossa tela, então
ele é limpo antes de aparecer: caracteres de controle fora, comprimento cortado
no mesmo limite do campo local. Sem isso um nome comprido estica o cartão até
estourar a coluna, e uma quebra de linha empurra o resto da faixa para fora. O
que a limpeza **não** resolve é alguém se chamar como outro — apelido é apelido.

No Ludo o nome entra como **complemento da cor**, e não no lugar dela: "Vermelho
(Ana)". A cor é a identidade do jogador naquele tabuleiro, e trocá-la pelo nome
cortaria a única ligação entre a faixa do placar e o peão.

### Som e vibração

Oito sinais para o app inteiro — toque, passo, captura, dado, dinheiro, carta,
fim e aviso —, e **não** oito arquivos por jogo. Um toque de peça soa igual no
xadrez, nas damas e no Ludo porque é a mesma coisa acontecendo; um banco por jogo
seriam cinco vocabulários que divergem no dia em que alguém trocar um deles.

Nenhum arquivo de áudio no repositório: **as ondas são geradas em código**. É a
mesma decisão do tabuleiro desenhado, das peças em primitivas e do QR escrito à
mão. Um efeito de 0,2 segundo é um envelope exponencial sobre ruído ou sobre duas
senóides — dez linhas de matemática contra um binário com licença a rastrear.

O que distingue um clique de um baque é **quanto tempo o envelope leva para
cair**, e não a nota. Por isso os números que importam em `sound.gd` são os
decaimentos: 34 é um estalo, 7 é uma nota que sustenta. O dado é ruído recortado
por uma modulação rápida, que é o que separa "quicando" de "chiado"; o dinheiro
são duas notas subindo e o aviso são duas descendo, porque usar o mesmo eixo para
as duas notícias é o que as torna reconhecíveis sem se confundirem.

O limite disso é honesto e vale dito: som sintetizado acerta o clique, o baque e
o chocalho, que são ataque curto e decaimento rápido. Ele **não faz timbre** —
uma moeda de verdade tem harmônicos que uma soma de senóides não reproduz sem
virar um sintetizador. Se um dia o app quiser textura em vez de sinal, é aí que
um pacote de amostras entra, e só a tabela de `_bake` muda.

O ruído sai de uma função de dispersão do tempo e não de `randf()`: assim as oito
ondas são **idênticas em toda execução**, e um som que muda a cada abertura do
app é um som que ninguém consegue julgar nem corrigir.

Tudo cabe em meio segundo. Num jogo de tabuleiro o som é **pontuação** — ele diz
que a coisa aconteceu e sai do caminho. Um efeito de dois segundos ainda está
tocando quando o jogador faz a escolha seguinte, e aí deixa de informar e passa a
atrapalhar. São quatro tocadores em roda e não um: o dado e o passo do peão se
sobrepõem por desenho, e um tocador único cortaria o primeiro no meio.

A **vibração** acompanha só os três sinais em que alguma coisa encosta — toque,
baque e dado — e é mais curta ainda, na casa dos 12 a 34 ms. Vibrar a cada evento
transforma o aparelho num alarme, e vibrar no fim da partida é comemorar com o
bolso do jogador.

Os dois interruptores nascem **ligados**, e são dois e não um: no ônibus se quer
a vibração sem o som, e numa mesa de quatro se quer o som sem o aparelho tremendo
na mão de ninguém. Eles gravam na hora, e não no "Salvar" — um interruptor não
tem momento de confirmar, ele já é a decisão. O de som toca ao ser ligado, que é
a única forma de responder "ligado como?" sem mandar o jogador abrir uma partida
para descobrir.

Toque no vazio não faz som. Quem errou o alvo por um dedo não precisa de uma
notificação disso, e num tabuleiro de 64 casas isso acontece o tempo todo.

### Animação

As animações existem por motivo funcional, não decorativo:

- **Movimento das peças** — sem isso o lance do oponente chega teleportado e o
  jogador não vê o que foi jogado. Cada trecho leva ~170ms, então uma sequência
  de capturas nas damas soma: um salto triplo demora o triplo, porque cada salto
  precisa ser visto.
- **Captura** — a peça capturada encolhe e some, e quem captura pula em arco por
  cima dela. Como o estado já foi aplicado quando a animação começa, `_play`
  copia o que havia nas casas **antes** de aplicar; sem isso a peça capturada
  sumiria de um quadro para o outro.
- **O painel de resultado espera o lance terminar de andar.** O lance que decide
  a partida é o que mais se quer ver, e um painel imediato o esconderia.
- **Indicadores de destino crescem ao aparecer** — a diferença entre "surgiu" e
  "sempre esteve" é o que confirma que o toque foi registrado.

O `_process` do tabuleiro só liga enquanto há xeque, lance em curso ou indicador
crescendo. Em repouso não custa quadro nenhum.

Fim de partida por **abandono** usa o mesmo painel de vitória e empate: sair no
meio é um desfecho como outro qualquer, e quem ficou precisa saber por que o
tabuleiro parou de responder.

### As peças desenhadas por código

O xadrez usa os SVGs de `assets/pieces/`; o que segue vale para as pedras de
damas, que continuam desenhadas, e para o caminho de reserva de qualquer peça
sem arquivo.

Cada peça é um **perfil torneado**: só a metade direita da silhueta é descrita, de
baixo para cima, e espelhada — que é como uma peça de xadrez é feita de verdade,
num torno. Garante simetria exata e corta o desenho pela metade. O cavalo é a
única exceção, por ser a única peça assimétrica do jogo.

Os perfis passam por Catmull-Rom, então poucos pontos de controle viram curva
contínua, e o volume vem de recortar a própria silhueta em faixas com
`Geometry2D` — sombra de um lado, realce do outro, sem shader.

Três armadilhas, todas com o mesmo sintoma (a peça simplesmente não aparece,
porque `draw_colored_polygon` desiste em silêncio quando a triangulação falha):

- **pontos colineares**: um trecho reto suavizado vira dezenas de pontos na mesma
  linha, e o ear-clipping recusa o polígono;
- **pontos de controle repetidos** numa spline *fechada* viram laço;
- **ultrapassagem da Catmull-Rom** no eixo de espelhamento cruza a silhueta com
  ela mesma.

A defesa é `_sanitize`, que une o polígono com ele mesmo: parece inútil, mas
`merge_polygons` usa Clipper, que resolve auto-interseção e devolve um contorno
simples.

### Decisões que talvez não sejam óbvias

**O codificador de QR é próprio.** A Godot não gera QR e nenhum addon era
necessário: `net/qr_encoder.gd` implementa modo byte, correção de erro nível M,
versões 1–9, Reed-Solomon em GF(256), os 8 padrões de máscara com escolha pela
pontuação de penalidade, e informação de formato/versão calculada por BCH em vez
de tabela decorada. São ~380 linhas; o payload com credenciais de Wi-Fi cabe na
versão 5 (37x37).

Escrever um codificador de QR é fácil; **verificar** um é que não é. Este ficou
semanas gerando códigos que nenhum leitor do mundo aceitava: o polinômio gerador
do Reed-Solomon era montado na ordem inversa da norma, e a divisão sintética
depende de `gen[0] == 1`. O resultado é indistinguível de um QR correto por
inspeção — padrões de função perfeitos, informação de formato conferindo com a
tabela publicada, máscara igual à que as bibliotecas escolhem, e os dados
corretos e no lugar certo. Só o ECC estava podre, que é exatamente onde o
decodificador desiste em silêncio.

Nenhum teste estrutural pega isso. O que pega:

- **`_check_generator_polynomials`** compara os polinômios de grau 10, 16 e 26
  contra os expoentes de α publicados na norma. É a única verificação do arquivo
  que não depende do meu código estar certo.
- **`_check_known_matrices`** guarda a impressão digital da matriz inteira para
  payloads fixos, validados por decodificador externo quando foram gravados.

O erro anterior valeu a lição: eu tinha "verificado" o Reed-Solomon
reimplementando o meu próprio algoritmo em outra linguagem e comparando com ele
mesmo. Isso não é teste, é eco. Verificação precisa de uma fonte independente —
aqui, a tabela da norma e um decodificador de terceiros (`jsqr`).

**Toda peça vem de SVG.** O conjunto está em `assets/pieces/` (18 arquivos, um
por espécie e cor) e o desenho por polígonos de `piece_renderer.gd` ficou como
caminho de reserva: espécie sem textura cai nele em vez de sumir do tabuleiro, e
é o que vai segurar a primeira peça de um jogo novo enquanto o desenho não chega.

A âncora da batalha naval é o único ícone que não é uma peça de verdade — o jogo
não tem peça que ande. Ela existe para responder "que jogo é este" na grade de
escolha e no cabeçalho, pelo mesmo `PieceRenderer` que o resto usa.

**Os cascos são três segmentos, não quatro navios.** `ship_bow`, `ship_mid` e
`ship_stern` se encadeiam casa a casa, e `WatersView` escolhe qual usar olhando
os vizinhos: sem vizinho adiante é proa, sem vizinho atrás é popa, entre os dois
é meio. Um arquivo por navio custaria quatro desenhos em quatro proporções
diferentes, e ainda assim quebraria no dia em que um navio mudasse de tamanho.

Vizinho "do mesmo navio" é vizinho da **mesma espécie**, e isso só funciona
porque cada navio tem a sua — dois cascos encostados nunca se fundem num só por
engano, e nenhuma casa precisa carregar um identificador de casco. Foi o motivo
de dar espécies distintas aos dois navios de três casas, que na caixa também têm
nomes diferentes.

A proa do desenho aponta para `+x`; na vertical o `WatersView` gira um quarto de
volta negativo (a fileira cresce para cima na tela) e soma meia volta quando o
tabuleiro está girado. O navio afundado é o mesmo desenho tingido de vermelho —
um quinto e um sexto arquivo diriam o que a cor já diz.

A troca não tocou em nenhuma tela porque `PieceRenderer.draw_piece` sempre foi o
ponto único de desenho de peça do jogo: tabuleiro, cartão de jogador, fileira de
capturas, linha de último lance e miniatura do menu passam todos por ele, com a
mesma assinatura. O corpo mudou; as cinco chamadas, não.

Duas coisas sobre importar SVG na Godot:

- **A rasterização é feita na importação, em escala fixa.** As peças aparecem em
  cinco tamanhos diferentes (casa do tabuleiro, avatar do cartão, 26px na
  fileira de capturas, 22px na linha de último lance, miniatura do menu), então
  os `.import` fixam `svg/scale=4.0` — 72px de origem viram 288px — com
  `mipmaps/generate=true`. Sem mipmap, o mesmo arquivo que fica bonito no
  tabuleiro serrilha na fileira de capturas.
- **As duas cores são o mesmo desenho com os dois preenchimentos trocados.** Dava
  para carregar seis arquivos e recolorir, mas isso pediria shader ou duas
  passadas; doze texturas de alguns KB é mais simples e mais previsível.

Glifos Unicode de xadrez (♔♕♖) nunca foram opção: *não existem* na fonte padrão
da Godot, e usá-los renderizaria caixas vazias no celular.

**O código de 6 caracteres não usa 0/O/1/I.** Ele é lido de uma tela e digitado
por outra pessoa; ambiguidade aqui vira suporte depois.

**Sem NFC "peer-to-peer".** O Android Beam foi removido da plataforma. O que
funciona hoje é assimétrico: anfitrião em Host Card Emulation, convidado em
reader mode — implementado assim em `android_plugin/`.

**O NFC não carrega o jogo, só a senha.** A taxa do NFC é baixa demais para ser o
transporte da partida; ele entrega ~60 bytes de credenciais e sai do caminho.
Mesma lógica para o QR.

**GDScript, não C#.** O projeto tem .NET habilitado, mas as duas coisas que
poderiam justificar C# (performance e bibliotecas) não se aplicam: a geração de
lances é trivial para um jogo sem IA, e o QR foi escrito à mão. Em compensação, o
export Android com C# ainda é mais chato (AOT, tamanho do APK, integração com os
plugins nativos). Se quiser migrar, `core/` é a parte que vale portar — ela não
depende de nada da Godot além de tipos básicos.

### Erros que valem registro

**Os nomes da mesa do Uno apareciam em umas partidas e em outras não.**

Numa mesa de quatro, quem entra aprende o nome do anfitrião no `welcome` e o dos
outros convidados só quando o `ready` deles chega — que costuma ser **depois** de a
cena da partida existir. O aviso `names_changed` chegava e redesenhava a mesa;
a coluna de jogadores à esquerda escrevia o nome uma vez, ao nascer, e nunca
mais. "Jogador 2" ou o nome certo, conforme quem ganhava a corrida — que é
exatamente o tipo de defeito que um teste com um aparelho só nunca vê.

A mesma leitura única escondia um segundo: a cadeira que vira máquina no meio da
partida continuava sem "(bot)" no cartão. E um terceiro, na ordem dos avisos:
`_drop_seat` emitia `bots_changed` **antes** de `seat_left`, e as três cenas —
que comentavam ler o nome "antes de a lista mudar" — liam a lista já mudada e
anunciavam "Jogador 3 (bot) saiu".

**O anfitrião que voltava abria uma partida nova.** Ver
[Quem recebe quem volta](#quem-recebe-quem-volta). O que faz valer registro é que
o teste de ponta a ponta de dois assentos **passava**: o anfitrião voltava, recebia
"oponente chegou" e a asserção ficava satisfeita — pelo caminho errado, um
`welcome` novo em vez de um `resume`. Só a asserção sobre o que **não** podia
mudar (a semente, o ritmo, o outro não receber uma mesa nova) pegou.

**O tabuleiro do Ludo exigia altura igual à própria largura, e a folha de prints
era cega para isso.**

`LudoView` declarava `custom_minimum_size.y = size.x`. Estava certo enquanto a
tela era uma **coluna**: ali a largura era o que sobrava, e reservar a mesma
altura evitava uma faixa morta entre o tabuleiro e o dado.

Deitado, a conta se inverte. Numa fileira `[placar][tabuleiro][dado]` a largura do
tabuleiro é a sobra — e ele passou a exigir essa sobra de volta em altura. A
fileira inteira estourava para fora da tela, levando junto o quarto cartão do
placar, que é o do próprio jogador.

O que faz o caso valer registro é **por que ninguém viu**. Em 16:9 a base deitada
é 768x432, a sobra dá 444, e ele pedia 444 numa faixa de 432: doze pixels, que não
aparecem em print nenhum. Num celular 2.17:1 a base vira ~938 de largura, a sobra
vai a ~614, e o estouro é de cento e oitenta pixels — metade da tela.

E a folha de prints rodava em **1280x720**, que é exatamente a proporção da base
do projeto. Ela conferia o único formato em que o defeito não aparece. Passou para
1560x720, a proporção de um celular moderno: um print que só sai certo na
proporção da base está conferindo o caso fácil, não o layout.

A regra de forma: **uma dimensão mínima derivada da outra é um acordo com o
sentido do layout**, e este foi trocado de coluna para fileira sem que o arquivo
que assinou o acordo ficasse sabendo.

**O bot de Bomberman andava em círculo, e a memória de alvo não era o conserto.**

O rastro era literal: `1,2 1,3 1,2 1,3` até morrer. O diagnóstico óbvio é que o
alvo é recalculado a cada tique e a escolha inverte quando a casa muda — e eu
implementei a correção óbvia, memória de alvo, e a saída ficou **byte a byte
idêntica**. Depois a correção seguinte, guardar o destino em vez do vizinho:
idêntica de novo.

Duas correções corretas em cima de um diagnóstico errado. O que faltava era
olhar em vez de deduzir: instrumentado, o bot estava **morto**, e o "círculo" era
o boneco tremendo em cima da divisa entre duas casas. Ele andava 32 unidades, o
centro cruzava a fronteira, `x / CELL` devolvia outra casa, a busca era refeita da
casa nova e apontava para trás.

A causa é uma linha que eu tinha **documentado e não implementado**: o comentário
de `_step_toward` dizia que o bot mira o centro da casa vizinha, e o código
comparava coordenadas de casa. Um comentário que descreve a intenção em vez do
código é pior que nenhum — foi ele que me fez procurar o bug longe daqui.

Duas coisas que valem guardar do episódio, além do bug:

- **saída idêntica depois de mexer no código é um dado**, não uma coincidência a
  ignorar. Da segunda vez que aconteceu, era o sinal de que eu estava consertando
  outra coisa;
- o estado do bot está registrado abaixo em vez de escondido atrás de uma
  asserção fraca.

**O bot de Bomberman é um esboço.** Ele foge do fogo, põe bomba, quebra caixa — e
se mata sozinho com frequência: com quatro máquinas na mesa, as quatro morrem em
uns dez segundos. `tests/bomber_probe.gd` guarda o **mecanismo** (a decisão sempre
sai, cabe num byte, mexe no mapa) e não finge medir qualidade. Quem for melhorá-lo
começa por `tests/bomber_bot_trace.gd`, que conta em qual dos três ramos cada
decisão cai — foi ele que encontrou os dois erros acima.

**O bot de xadrez passeava com a torre, e não era a avaliação.**

O sintoma: depois que o adversário rocava, o bot movia a torre uma casa e
devolvia no lance seguinte — `Tf1 Te1 Tf1 Te1` — até uma captura ou um xeque
mudarem a posição. Parece defeito de avaliação, e a avaliação estava certa: nas
profundidades 1, 2 e 3 o melhor lance daquela posição era `d4`, com folga.

O bot não escolheu a torre. Ele **nunca chegou a escolher**. `Bot._rank`
devolvia uma lista vazia quando o relógio estourava no meio da rodada, e
`_decide` caía num padrão inicializado com `moves[0]` — o primeiro lance que o
gerador produz, pontuado por ninguém. O gerador varre o tabuleiro de a1 para h8,
então `moves[0]` é o lance da peça na casa mais baixa. Antes do roque é o cavalo
de b1 e o bot parecia normal; depois do roque a primeira linha abre e vira a
torre. Daí "ele fica perdido com o roque do inimigo".

Por que o relógio estourava sempre: **uma rodada de profundidade 1 custava
2263 ms**, e os níveis Fácil e Médio têm 250 e 900 ms. Nenhum dos dois completava
uma rodada, nunca, em posição nenhuma.

A lição de método é a que vale guardar: o sintoma apontava para a avaliação, e
medir apontou para o relógio. `tests/bot_bench.gd` existe por isso — ele separa
"a busca prefere isto" de "a busca não teve tempo de olhar", que é a distinção
que o tabuleiro não mostra.

**A primeira correção não bastou, e o motivo é instrutivo.** Garantir que o lance
devolvido tinha sido pontuado consertou a abertura e não consertou o meio-jogo:
numa posição cheia a rodada de profundidade 1 custava 7,9 s, nenhum nível a
terminava, e os poucos lances que davam tempo de pontuar eram sempre os
primeiros da lista — os da mesma torre. O bot passou de "joga a torre sem olhar"
para "joga a torre depois de olhar", que é o mesmo lance. Uma correção que
melhora o mecanismo sem mover o sintoma é uma correção pela metade, e só a
segunda medição mostrou isso.

Cinco correções, nesta ordem:

- **nunca devolver um lance não pontuado.** Uma rodada cortada agora devolve o
  que mediu, e o último recurso é uma avaliação de um lance **sem relógio** —
  fraca, e olhada. `_test_bot_starved` fixa isso com um orçamento de 1 ms;
- **legalidade só onde ela pode falhar.** Um lance pseudo-legal só é ilegal se
  mexer o rei, se o rei já estiver em xeque, se a peça estiver pregada, ou se for
  en passant. Antes cada um dos ~35 custava uma cópia do tabuleiro e um
  `_is_attacked` inteiro. `generate_moves`: 0,650 → 0,225 ms;
- **teto na busca de sossego.** Ela não tinha — e era ali que ia quase todo o
  tempo. Seis níveis, e o número foi **medido**: com quatro a ordenação da raiz
  muda, com seis as notas saem idênticas às de antes. Profundidade 3: 101 s → 8,4 s;
- **ordem estática na raiz.** A primeira rodada é ordenada por avaliação
  imediata, não pela varredura do tabuleiro. Assim uma rodada cortada devolve o
  melhor entre os lances **promissores**, e não entre os mais à esquerda. Custa
  dois milissegundos e é o que finalmente move o sintoma;
- **capturas ordenadas por material, e poda por diferença.** Comer a dama
  primeiro levanta o `alpha` de uma vez, e a partir daí a captura que não alcança
  o que já se tem é descartada sem ser buscada — inclusive todas as menores que
  ela, porque a lista está ordenada. Meio-jogo, profundidade 1: 7,9 s → 2,6 s.
  `Ruleset.capture_gain()` existe para isso sem o `Bot` aprender xadrez: ele
  pergunta quanto vale a captura, como já pergunta quanto vale a posição.

Antes de tocar na legalidade, o perft foi de profundidade 3 na posição inicial
para profundidade 4 mais Kiwipete e a posição de final da lista clássica. A
posição inicial é mansa — quase nenhum lance dela é ilegal, e um gerador que
**nunca** conferisse legalidade passaria nela. Otimizar a conferência com aquele
perft como rede seria trabalhar sem rede.

**A coluna do placar do Ludo era indexada por posição, e ganhou um vizinho.**
`_update_scoreboard()` pegava a faixa de cada cor com `%Scoreboard.get_child(player)`,
e `_build_scoreboard()` limpava a coluna com um laço sobre **todos** os filhos.
Nenhum dos dois estava errado enquanto a coluna fosse só das quatro cores.

A faixa de contexto entrou no topo dela e os dois lados quebraram no mesmo
instante: a limpeza apagou a faixa junto com as cores, e `get_child(0)` passou a
devolver um `HFlowContainer` onde se esperava um `PanelContainer`. O segundo deu
erro de tipo e apareceu na hora; o primeiro é o que teria escapado — uma faixa
que simplesmente não aparece não avisa ninguém.

A correção é guardar as faixas numa lista em vez de procurá-las por posição.
Vale registro porque a lição não é sobre o Ludo: **indexar filhos por posição é
um acordo com o futuro**, e quem o assina é quem escreve o contêiner, não quem
vai acrescentar um nó nele depois.

**O botão de voltar do sistema fechava o app de qualquer tela.** O padrão do
Godot é `SceneTree.quit_on_go_back = true`, e ninguém tinha desligado — o gesto
mais natural do Android matava o processo no meio de uma partida em rede, e quem
estava do outro lado via um abandono.

O que faz este caso valer registro não é a linha que faltava: é que a pilha de
navegação **já existia** e estava certa. Toda tela tinha o seu botão "Voltar",
escrito, testado e correto; o que faltava era o gesto do sistema chegar até ele.
Um padrão global que ninguém escolheu ganhava de nove decisões que alguém tomou.

A correção mora no autoload `Nav`, e ele não guarda pilha nenhuma: entrega o
gesto ao método `go_back()` da cena aberta, que chama o mesmo caminho do botão.
Uma segunda pilha seria uma segunda resposta para "onde eu estava", e a que
ficasse desatualizada mandaria o jogador para uma tela que ele nunca abriu.

Duas escolhas de forma que o resto do app repete:

- **quem esquece o método volta ao menu, não fecha o app.** A falha de uma tela
  nova precisa ser barata. `scene_probe.gd` varre `res://scenes/` — e não uma
  lista escrita à mão, que seria a mesma coisa a esquecer duas vezes;
- **a única tela que fecha é a inicial.** O comportamento antigo nunca esteve
  errado: estava aplicado em todo lugar.

E o teste da dublê custou uma lição própria: `set_current_scene` **recusa em
silêncio** um nó que não seja filho de `root`. Pendurada na suíte, a dublê nunca
virou cena atual, `Nav` caiu no caminho de emergência e trocou a cena — levando
junto o teste que estava rodando. O erro apontava para o `_ready()` da suíte, a
uns setecentos linhas de onde a causa estava.

**`MatchState.clone()` não isolava os vetores de `meta`, e o comentário dizia que
isolava.** O comentário raciocinava assim: `meta` guarda inteiros e
`PackedInt32Array`; vetor empacotado é cópia-na-escrita; logo a cópia rasa basta.
A primeira e a segunda premissas são verdadeiras e a conclusão é falsa.

A cópia-na-escrita dispara quando se escreve por uma **variável**:
`var v := meta[K]; v[i] = x` copia antes de escrever e o original fica intacto —
que é como `LudoRules` sempre fez, e por isso o Ludo nunca teve o problema.
Escrever pelo **caminho** — `meta[K][i] = x` — vai direto ao vetor guardado no
dicionário, que a cópia rasa deixou compartilhado entre a posição e o clone.

O sintoma seria a variante que o bot explora vazando para a partida de verdade,
sem nenhuma mensagem, meses depois de alguém ter escrito a linha errada. Achado
pelo teste de clone de `monopoly_probe.gd`, escrito exatamente para desconfiar
daquele comentário.

A correção é estrutural, não documental: `clone()` percorre `meta` e duplica todo
valor de tipo empacotado. Custa um `typeof` por chave nos jogos que não usam
vetor nenhum ali — nenhum custo — e transforma "todo mundo que escreve reatribui"
de convenção em garantia. `Array` e `Dictionary` aninhados continuam proibidos em
`meta`: isolar aqueles é a cópia profunda que foi removida de propósito.

**O assento de quem falou chegava do servidor e era jogado fora.** O relay
carimba o remetente ao repassar cada mensagem — é a única coisa da mensagem que
um cliente adulterado não consegue forjar — e `net_link.gd` recebia esse número
num parâmetro chamado `_from_seat`, com um comentário prometendo que "quem vai
precisar dele é o protocolo de N jogadores, no passo seguinte".

O passo seguinte não veio, e o Ludo (quatro) e Metrópole (dois a seis) entraram
em produção em cima disso. O resultado: **qualquer assento podia jogar a vez de
qualquer outro.** O receptor validava o lance contra as próprias regras, então
ele tinha de ser legal para o jogador da vez — mas ninguém conferia se quem
mandou *era* esse jogador.

A lição não é sobre rede. É sobre o que a legalidade responde: um lance legal
para o jogador da vez é legal olhando só o tabuleiro, **venha ele de quem vier**.
"Este lance existe" e "este lance é seu" são duas perguntas, e o gerador de
lances só responde a primeira. Até uma mesa de dois estava exposta — lá o
oponente podia mandar um lance das **nossas** peças.

Em Metrópole valia dobrado por causa da troca: com uma proposta na mesa quem
decide é o destinatário, então sem conferir o remetente quem propôs mandava o
próprio "aceito".

**`opponent_left` era um conceito de mesa de dois aplicado a mesas de seis.** Ele
encerra a partida, o que está certo quando a mesa tem duas cadeiras. Numa de
seis, o 4G de uma pessoa caindo acabava o jogo das outras cinco — e o assento de
quem sumiu chegava em `_on_relay_peer_gone(_seat)`, também descartado.

Agora mesas maiores emitem `seat_left`, a cadeira vira máquina e quem ficou
continua. A saída já existia pronta: é o mesmo bot da sala que não enche.

Isso obrigou a mexer numa regra que parecia estável: "quem executa um bot é o
assento 0, sempre". Ela deixa de bastar quando um assento vira máquina no meio da
partida — se quem sai é o 0, ninguém sobra para rolar o dado das máquinas e a
mesa para de andar. Virou "o menor assento que ainda é humano", que continua
sendo um aparelho só, que é o que importava desde o começo.

**Metrópole entrou no menu com o ícone do Ludo e sem arte de fundo, e passou
despercebido por semanas.** As duas linhas ficavam iguais de relance — o mesmo
dado branco, o mesmo texto, e a de Metrópole lisa enquanto as outras quatro
tinham o tabuleiro desfocado atrás.

Nenhuma das duas coisas dava erro. O ícone era um `Board.Kind.DIE` legítimo,
escolhido por ser o único que servia quando o jogo entrou no catálogo. E
`card_art.gd` percorre `Game.GAMES` inteiro: ele **tentou** gerar a arte, caiu no
ramo genérico do `BoardView`, e a única pista foi um PNG que nunca apareceu na
pasta.

Um jogo novo no catálogo precisa de três coisas, e só uma delas o catálogo
cobra: a entrada em `GAMES` (cobrada), um ícone que não seja de outro jogo (não
cobrado) e um ramo em `card_art.gd` (não cobrado, e silencioso quando falta). As
duas últimas ficaram — e o ícone virou `Kind.HOUSE`, uma casinha, porque a
alternativa era eleger uma das seis peças de jogador como o rosto do jogo.

**Arquivo novo em `assets/` sem `.import` é desenhado como ausente, sem erro
nenhum.** O SVG do ícone e o PNG da arte foram escritos direto no disco, fora do
editor. O `ResourceLoader.exists()` do cartão devolvia falso e a linha saía lisa;
o `load()` da peça devolvia `null` e o ícone simplesmente não aparecia. Nenhum
dos dois caminhos reclama, porque os dois foram escritos para tolerar arte
faltando — que é a decisão certa e o que torna isto invisível.

A cura é uma passada de importação, e ela agora está escrita no cabeçalho de
`card_art.gd`:

```bash
godot --headless --path . --editor --quit
```

**`toggle_mode` faz o botão desenhar o estilo pressionado, e ele ganha da
variação do tema.** Os dois interruptores de som e vibração nasceram como botões
de alternância com `theme_type_variation = ChipSelected`, e apareceram
preenchidos de latão — do mesmo tamanho e da mesma cor do "Salvar" logo abaixo. A
tela de ajustes passou a ter três ações principais, sem que nenhuma linha
estivesse errada.

Em modo de alternância o Godot usa o stylebox `pressed` enquanto o botão está
ligado, e um stylebox do tema para um estado específico ganha da variação
inteira. É a mesma razão de os chips do menu — ritmo, formato, jogadores — serem
botões **comuns** que trocam de variação no `pressed`: o estado ligado é uma
escolha de aparência, e entregá-lo ao mecanismo de alternância é entregá-lo ao
tema.

**Um `_ready` que escreve o padrão da classe apaga a escolha de quem sabia mais
que ele.** `DieView._ready` punha `mouse_filter = MOUSE_FILTER_STOP` — que já é o
padrão de `Control`. A linha não fazia nada, **exceto** desfazer a escolha de
quem tivesse decidido o contrário antes do `add_child`.

E alguém tinha: em Metrópole os dois dados não aceitam toque, porque cada um
sorteando por conta produziria um lance que não existe. A tela escrevia `IGNORE`
e o `_ready` desfazia. O dado girava ao ser tocado, parava num número que a
partida ignorava — e ainda gastava um dos dois avisos de "dado parou", pisando na
rolagem seguinte.

A regra que sai disto: **escrever um valor igual ao padrão não é inofensivo**. É
um `set` como qualquer outro, e ele ganha de quem escreveu antes. `_ready`
escreve só o que a classe realmente muda.

**A rolagem viajava e a notícia dela não.** O lance é `[ROLL, d1, d2]` e chegava
inteiro do outro lado — mas quem recebia aplicava direto: o peão saía andando e
os dados daquela tela continuavam mostrando o número da vez anterior. Quem não
rolou nunca via o que foi tirado, só a consequência.

A causa é de estrutura: a animação dos dados morava dentro de `_roll()`, o
caminho de **quem sorteia**. Quem recebe entra pelo outro caminho e não tinha
como passar por ela. Virou uma função só, `_spin_dice(d1, d2)`, usada pelos dois
— e o caso que ficaria de fora quando escrito duas vezes é sempre o de rede, que
é o mais difícil de ver acontecer.

**A câmera livre se desmanchava a cada peão que andava.** `walk()` chamava
`recenter()`, com o argumento de que o peão andando é o momento em que a câmera
automática vale o que custa. O argumento é bom e a conclusão estava errada: quem
pegou a câmera pegou para olhar alguma coisa, e o enquadramento se desfazia a
cada turno — inclusive nos dos outros jogadores.

Uma vista que se desmonta sozinha não é uma vista que se possa usar. O controle
manual agora só termina quando quem o pegou o devolve, no "Recentrar" — que está
na tela justamente enquanto a câmera está solta.

**"Encolher os currais faz a célula crescer" era falso, e foi dito com número
inventado.** A sugestão saiu daqui, com um "~30%" que ninguém tinha medido — e
ela ia custar uma reforma inteira do tabuleiro para não mudar nada.

O tabuleiro do Ludo tem 15 casas de lado porque o **braço** mede 6. É o braço que
produz as 13 casas de trilha por quadrante (5 ao longo dele mais 6 subindo a
coluna do centro, mais as 2 da virada), e 13×4 = 52, que é a trilha do jogo. Os
15 são 6 + 3 (centro) + 6.

O curral não entra nessa conta: ele é a **sobra do canto**, o quadrado de 6×6 que
o braço deixa livre. Desenhá-lo menor não devolve espaço para nada — a célula
continua sendo `lado / 15`, e o lado continua limitado pela altura da tela.

O que aumenta o peão é o peão. Ele era desenhado a 0,88 de célula (0,94 aqui
vezes os 0,94 que o `PieceRenderer` já tira de folga) e passou a 1,09, **+24%**:
ele transborda a casa, e pode — é mais alto que largo, a casa é quadrada, e o que
se lê num tabuleiro de 15 por lado é a silhueta, não a moldura em volta dela.

O curral encolheu mesmo assim, e por outro motivo: ele deixou de ser um bloco
maciço de um quarto do tabuleiro e passou a ter ar em volta, o que faz a **cruz**
virar a forma dominante — que é o que se percorre com o olho durante a partida.
Ganho de leitura, não de tamanho.

Lição: um palpite de layout com número redondo é um palpite. A conta que
importava — de onde vêm os 15 — estava escrita no próprio arquivo, em `RING_PATH`.

**Uma regra de casa disfarçada de regra do jogo travava o Ludo no ponto mais
visível dele.** `_target` recusava pousar em cima de peão da própria cor. O único
lugar onde um peão nasce é a casa de saída — então, com um peão seu lá, um 6
**não tirava outro da base**.

O segundo efeito era pior que a recusa e escondia o primeiro: sobrando um lance
só, a tela joga sozinha. Essa conveniência é antiga e defensável, mas aqui ela
recebia uma lista de um lance porque a *outra* regra tinha apagado os legítimos —
e o 6 saía andando com o peão que já estava fora, sem ninguém ter escolhido nada.
O relato que chegou foi esse: "ele movimenta minha peça sem input meu".

A lição é sobre **conveniências que amplificam bugs**. "Um lance só, jogue
sozinho" é correta quando a lista está certa; quando ela está errada, a
conveniência transforma uma recusa visível numa ação inexplicável. Uma tela que
tivesse pedido confirmação teria mostrado o bug em vez de escondê-lo.

O teste que afirmava a regra errada passava havia meses. Ele não estava
verificando o jogo — estava verificando o código.

**A paisagem do Ludo não deixou o tabuleiro maior, e isso foi medido antes.** O
tabuleiro do Ludo é quadrado, e em retrato ele já era limitado pela largura: 404
pixels de base contra 402 deitado. Girar não muda o tamanho dele.

O que muda é o **resto** da tela: em retrato sobravam mais de cem pixels de nada
entre o dado e o botão de sair, com as quatro cores espremidas numa faixa baixa.
Deitado, elas viram uma coluna da altura do tabuleiro, com nome e placar em
linhas separadas, e o dado ganha a coluna oposta — o mesmo arranjo de Metrópole,
que é o que faz os dois jogos de mesa do app se parecerem entre si.

Fica registrado porque o pedido era "melhorar a visibilidade" e a paisagem
responde só metade disso. A outra metade continua sendo o desenho do tampo: o
tabuleiro é 15×15 e os quatro currais consomem 36 células cada só para guardar
peão parado.

**No Android cada dedo é dois eventos, e o segundo virava um dedo fantasma.**
`emulate_mouse_from_touch` vem ligado de fábrica no Godot, então todo toque gera
o evento de tela **e** um de mouse sintetizado. A câmera de Metrópole conta
dedos: um é órbita, dois são pinça. Se o evento de mouse chegasse primeiro, ele
registrava o ponteiro -1 antes de o nó saber que estava num aparelho de toque — e
a partir daí a mesa tinha dois "dedos" com um dedo só encostado.

O sintoma no aparelho era exato e enganoso: **só o zoom respondia**. Girar era
lido como pinça de um dedo só, que não muda distância nenhuma. No desktop, onde
não há evento de tela, tudo funcionava.

A correção não é escolher um dos dois caminhos por adivinhação de ordem: o
primeiro toque de verdade **apaga o ponteiro que o mouse emulado deixou**, e a
partir dali os eventos de mouse são ignorados. Desligar a emulação no projeto
resolveria isto e quebraria todos os botões do app, que dependem dela.

**Uma preferência não é uma garantia.** A câmera que segue o peão mira "um pouco
à frente dele, puxado para o meio do tabuleiro". O puxão existe porque mirar só à
frente joga a mira para fora do tampo perto dos cantos — e a 0,55 ele resolvia
esse caso e criava outro: somado ao avanço, punha a mira a quase quatro unidades
do peão num quadro cuja meia-largura é cinco. O peão vivia encostado na borda e,
em certas casas, saía dela.

O erro de forma foi tratar uma **preferência** ("olhe mais para dentro quando
der") como se ela protegesse o caso ruim. Ela não protege — ela o torna raro, que
é diferente, e o raro aparece quando alguém joga de verdade. Agora há as duas
coisas: o puxão continua sendo a preferência, e uma coleira garante que a mira
nunca fica a mais de 2,4 casas do peão, custe o que custar ao enquadramento. O
peão da vez é o assunto da tela, e uma câmera que o perde não está seguindo
ninguém.

**Uma folga de tema desenhada para painel de menu, herdada por uma faixa de
coluna.** `AppTheme.box()` embute 18 de folga horizontal e 14 vertical, e está
certo — ela foi escrita para painel, onde o ar em volta do conteúdo é o que faz a
tela respirar. A faixa de jogador de Metrópole usava a mesma função, e aqueles 28
verticais eram mais altura que o próprio conteúdo dela: com seis jogadores a
coluna passava dos 416 da base deitada e a última faixa saía da tela junto com os
botões do rodapé. Os 36 horizontais eram, de quebra, o motivo de a coluna nascer
mais larga que os 136 que ela pedia.

Lição: um construtor de estilo compartilhado carrega as **folgas de quem o
escreveu primeiro**. Quem o reusa num contexto de outra escala tem de zerá-las e
dar as suas — que aqui já existiam, num `MarginContainer` por dentro.

**Uma camada que se ancora no próprio `_ready`, começando escondida, fica com
tamanho zero.** A tela de fim de Metrópole é um `Control` de tela cheia com um
fundo escuro e um painel centrado. Ela chamava `set_anchors_preset(FULL_RECT)`
dentro do próprio `_ready` — que roda no `add_child`, quando o nó já está na
árvore — e ficava com tamanho zero: o fundo não escurecia nada, e o painel
aparecia encostado no canto de cima à esquerda em vez de centrado. A camada da
mesa de troca, idêntica em tudo menos nisso, funcionava: quem escreve o preset
dela é a cena, **antes** do `add_child`.

O sintoma engana porque nada falha — a camada aparece, os botões funcionam, e o
que se vê é "o painel está torto". Fica registrado porque a diferença entre os
dois casos é uma linha de lugar, não de conteúdo: **preset de âncora se escreve
antes de entrar na árvore**, e o nó começar invisível é o que impede o layout de
voltar para corrigir depois.

**A recusa do servidor virava "conexão instável" e noventa segundos de espera.**
O relay manda o motivo e fecha no mesmo fôlego — `{"t":"error","reason":…}`
seguido de `close(1008)`. O cliente, ao ver o socket fechado, chamava `_drop()`
**sem ler o que ainda estava na fila**: o frame com o motivo era descartado, a
queda era tratada como falha de rede, e o laço de reconexão repetia a mesma
pergunta a cada meio segundo até desistir aos 90s. Um código digitado errado
ficava indistinguível de internet ruim.

Duas correções, e as duas são necessárias: **drenar os pacotes pendentes antes
de tratar o fechamento**, e **não reconectar quando o código de fechamento é
1008** — que é resposta, não queda. Coberto em `tests/relay_smoke.gd`, que
entra numa sala inexistente e exige o motivo certo em menos de 10 segundos (na
prática, 0,3s).

Lição: num protocolo em que o servidor fecha logo após falar, "socket fechado"
não significa "não há mais nada a ler". A ordem correta é sempre drenar, depois
tratar.

Da primeira rodada de testes em aparelho: a tela de pareamento abria, o código
aparecia, o QR aparecia, e **nenhum dos caminhos conectava**. Nenhuma mensagem
de erro, nenhum aviso no log. Três causas, todas silenciosas — mais uma quarta,
achada depois.

> As duas primeiras falam do Nearby Connections, que **não existe mais** no
> projeto (veja [O que saiu](#o-que-saiu-nearby-connections)). Ficam registradas
> porque as lições valem para qualquer transporte.

**`leave()` desligava o que a tela tinha acabado de ligar.** `_setup_host()`
chamava `Net.advertise_nearby()` e, três linhas depois, `Net.host_match()` — que
começava com `leave()`, que chamava `disconnect_peer()` no bridge, que chamava
`stopAdvertising()` no plugin. O anúncio Nearby morria antes de qualquer
convidado poder vê-lo. A correção foi separar o desligamento por transporte:
`leave()` continua derrubando tudo, mas abrir um transporte só derruba o dele.

Lição: uma função de limpeza global chamada no caminho de inicialização é uma
armadilha. Quanto mais transportes convivem, mais cara ela fica.

**Sinal recebido com os argumentos trocados.** A ponte do hotspot declarava
`hotspot_ready(ssid, passphrase, host_ip)`; a tela recebia com
`_on_hotspot_ready(host_ip, ssid, passphrase)`. A Godot conecta sinais por
posição, não por nome, então o SSID entrava como endereço IP e ia parar dentro
do QR — que passava a anunciar um endereço que não existe. Nenhum tipo era
violado: os três parâmetros são `String`.

Lição: com uma assinatura toda do mesmo tipo, o compilador não ajuda. Vale
manter a mesma ordem dos dois lados por disciplina, e nomear com o significado
(`ssid`, não `first`).

**Nenhum caminho atravessava NAT.** Os três transportes de então — Nearby,
hotspot, ENet — precisavam de proximidade física ou de rota IP direta. Com um
jogador no Wi-Fi de casa e o outro no 4G, não havia caminho *nenhum*, e o
sintoma era o mesmo dos dois bugs acima: espera silenciosa. Faltava um
componente, não um ajuste — daí o relay.

**Uma dependência mexia no aparelho sem pedir.** Descoberto na rodada seguinte:
abrir a tela de entrar numa partida **ligava o Wi-Fi do celular**. Ninguém no
código do jogo chamava `setWifiEnabled` — quem ligava era o Nearby Connections,
que administra os rádios por conta própria quando `startDiscovery` é chamado. O
comportamento está documentado pelo Google e mesmo assim não aparece em lugar
nenhum do código do app; só sai no aparelho.

Lição: efeito colateral de SDK de terceiro sobre o estado do aparelho não
aparece em revisão de código, porque não há linha para revisar. Vale listar o
que cada dependência toca fora do processo — rádios, permissões, serviços — e
não só o que ela oferece de API. Foi o que fez o Nearby sair do projeto.

O que ficou disso: `tests/pairing_probe.gd`, que abre a tela nos dois papéis e
verifica que cada caminho é *oferecido* — a sala existe, o código sobreviveu à
abertura do servidor, o payload do QR é válido. Não prova que conecta (isso
depende do rádio do outro lado), mas os três erros acima teriam sido pegos.

---

## Limitações conhecidas

- **Os plugins Android estão compilados e dentro do APK** (os três `meta-data`
  e o serviço HCE aparecem no manifesto final), mas **não foram testados em
  aparelho** — NFC e hotspot local não funcionam em emulador e exigem dois
  celulares. O que está verificado é que o app carrega os singletons; o
  comportamento de rádio não.
- **A pasta do projeto não pode conter `&`** se você for exportar com Gradle. A
  Godot chama `gradlew.bat` pelo `cmd.exe` sem aspas e o `&` corta a linha de
  comando. O mesmo vale para `apksigner` e outras ferramentas do Android SDK
  chamadas por fora. Contorno atual: um junction sem o caractere.
- **O bot não tem livro de aberturas nem tabela de transposição.** Ele reavalia
  a mesma posição toda vez que ela reaparece por outro caminho, e joga a abertura
  procurando como joga o meio-jogo. Um nível "Difícil" com transposição valeria
  mais um lance de profundidade pelo mesmo tempo.
- **O bot não administra o relógio, só evita perdê-lo.** A partida limita cada
  reflexão a um vigésimo do tempo que resta a ele, o que dá umas vinte jogadas de
  folga a qualquer altura. Mas ele não pensa mais na posição difícil e menos na
  fácil, e não acelera quando está ganhando — gasta o teto sempre.
- **A corrente de lances planejados para em quatro.** Não é limite de memória —
  são oito inteiros. É limite do que cabe legível no tabuleiro e do que vale a
  pena planejar sobre uma hipótese que ignora o oponente: o quinto elo pressupõe
  quatro lances seguidos dele sem consequência nenhuma.
- **Empate por repetição tripla não é detectado** no xadrez (50 lances e material
  insuficiente estão). Falta guardar o hash das posições.
- **Sem desfazer.** O `MatchState` guarda a lista de lances (`history`) e a tela
  já a lê para a notação e as capturas, então sai de cima do que existe.
- **A lista completa de lances não é visível.** `_notation` existe e está
  correta; só a linha do último lance é exibida. Um painel com a partida inteira
  faria sentido em tablet ou paisagem.
- **O histórico não é exportável.** A notação é gerada para leitura na tela; sair
  daí para PGN pediria o cabeçalho de tags e a numeração completa.
- **O relógio confia nos dois aparelhos.** Cada lado corre o próprio cronômetro e
  manda o valor junto com o lance; um cliente modificado poderia mentir sobre
  quanto tempo gastou. Sem servidor autoritativo não há como impedir — e o
  relay, de propósito, não conhece as regras.
- **O relay não escala horizontalmente.** As salas moram na memória de um
  processo; duas instâncias atrás do mesmo endereço põem anfitrião e convidado em
  processos diferentes e eles nunca se acham, e o sintoma do lado do jogador é
  "nenhuma partida com esse código" — que parece erro de digitação. O `fly
  launch` cria duas máquinas por padrão, então o problema aparecia sozinho; hoje
  **a esteira de deploy desfaz isso a cada publicação** (`fly scale count 1`) em
  vez de depender de alguém lembrar. Uma instância aguenta na casa dos milhares
  de partidas; o limite é número de conexões, não CPU. Detalhes em
  [`relay/README.md`](relay/README.md).
- **Numa mesa de dois a janela de reconexão é de 90 segundos.** Um túnel longo ou
  o celular descarregando encerram a partida. Numa mesa maior a cadeira fica com
  um bot, e a volta vale enquanto houver alguém na sala (até as quatro horas de
  vida dela).
- **O laço de retentativa da ponte não tem teste automatizado.** A volta em si tem
  (`tests/rejoin_smoke.gd`: queda sem aviso, chave, anfitrião voltando), e o
  servidor também (`relay/src/relay.test.ts`). O que foi verificado só à mão é a
  ponte reconectando **sozinha** depois de perder a rede, porque derrubar a rede
  de dentro do processo Godot exigiria uma API só para o teste.
- **Quem volta disputa um instante com o bot.** Se a máquina já escolheu o lance
  da cadeira quando a pessoa senta, esse lance entra — ele saiu antes do `resume`,
  e todos os aparelhos o validam com a lista de máquinas daquele momento. A pessoa
  reassume a mão a partir do lance seguinte.
- **Sem internet não há multiplayer.** Toda partida em rede passa pela sala no
  relay. Dois aparelhos lado a lado, ambos offline, só jogam passando o aparelho
  (que o modo mesa torna desnecessário) — o NFC entrega o código, não a partida.
- **O relay é ponto único de falha.** Ele fora do ar significa nenhuma partida em
  rede, para ninguém. É o preço de ter removido os outros caminhos, e foi
  cobrado de propósito: eles custavam mais em permissões e em espera do que
  rendiam em alcance.

## Próximos passos naturais

1. Testar o NFC em dois aparelhos físicos — é o único canal que nunca rodou fora
   do emulador.
2. Batalha naval numa partida real entre dois aparelhos: a troca de frotas e o
   reenvio delas na reconexão só foram exercitados por teste, nunca por rede de
   verdade.
3. Repetição tripla + botão de propor empate/desistir.
4. Livro de aberturas curto para o bot, para os primeiros lances pararem de ser
   procurados do zero toda partida.
5. Tabela de transposição no bot. É a próxima melhoria de verdade da busca: hoje
   ele reavalia a mesma posição toda vez que ela aparece por outro caminho, e no
   mesmo tempo isso valeria mais um lance de profundidade.
6. Metrópole num aparelho de verdade. É o único lugar do app com um `SubViewport`
   de 1536² **mais** uma cena 3D, em paisagem, e o risco térmico nunca foi
   medido — só o desenho foi julgado, em prints de desktop.
7. Timbre no som, se um dia ele for pedido. As oito ondas sintetizadas acertam o
   sinal e não fazem textura — é onde um pacote de amostras entraria, trocando só
   a tabela de `_bake`.
8. Sinuca em rede numa partida de verdade, e um smoke dela na esteira. A física é
   determinística por construção e há teste provando que a mesma tacada dá a mesma
   mesa **no mesmo binário**; o que nunca foi exercitado é um ARM e um x86
   chegando ao mesmo resultado, que é exatamente o que a quantização da tacada
   existe para garantir.
9. Efeito na sinuca, se ele um dia valer o preço. Ele pede rotação, atrito lateral
   e uma integração mais sensível a erro — e a primeira coisa a quebrar seria a
   igualdade entre os dois aparelhos, que é a propriedade em que a rede do jogo
   inteiro se apoia.
