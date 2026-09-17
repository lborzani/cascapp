# Redesenho do Cascapp — direção "Boteco"

Branch: `feature/redesign-ui` (a partir de `develop`)
Conceitos aprovados: https://claude.ai/artifact/9o1wiRmsRdLm9gMKhAKcEK

## 1. Objetivo

Refazer a interface e a experiência de uso do app inteiro na direção **A · Boteco**:
a mesa do bar onde o rolê acontece, puxada do próprio logo (caneca de chopp).
O que é **do jogo** fica exatamente como está; o que está **em volta** do jogo é
refeito.

Três decisões tomadas na aprovação:

1. Direção **A · Boteco**, com as seis mudanças de uso da seção 5.
2. **Como jogar** com páginas de regras por jogo e formato, e o painel "Regras
   desta mesa" dentro da partida. Sem tutorial jogável e sem dicas de primeira
   partida.
3. Tabuleiros que não estavam na lista de intocáveis **ficam como estão**; só a
   moldura e a sombra em volta acompanham o tema.

## 2. O que não muda

### Intocáveis (pedido explícito)

| Coisa | Onde mora | Regra |
| --- | --- | --- |
| Logo | `assets/icon/*` | Nenhum pixel. |
| Peças de xadrez, damas e Ludo | `assets/pieces/*.svg`, `scenes/piece_renderer.gd` | Nenhuma forma, cor ou contorno. |
| Barcos da naval | `assets/pieces/ship_*.svg` e o desenho deles | Idem. |
| Tabuleiro de Metrópole | `ui/monopoly_board_3d.gd`, `ui/monopoly_face.gd`, `ui/monopoly_token.gd` | Idem — inclui peões, casas, hotéis, a marca da cadeia e o destaque de casa, que ganharam cor fixa. O fundo da sala em volta da mesa segue o tema: é ambiente, não mesa. |
| Cartas de Uno | `ui/uno_card.gd` | Idem — frente, verso, o leque e o véu da carta apagada. |

`ui/monopoly_card.gd` **não** está na lista: ele é o painel que mostra a carta de
Sorte ou Cofre sorteada, interface por cima da mesa, e é redesenhado na etapa 4.

Os desenhos protegidos não leem nada do tema que muda: usam `AppTheme.legacy_font()`
(a fonte do sistema de antes) e constantes de cor próprias. A garantia é por
imagem — `tests/image_diff.gd` compara as folhas de cartas e peças e o miolo do
tabuleiro contra uma referência renderizada antes do redesenho, e a resposta
aceitável é zero pixels diferentes.

### Ficam como estão, só a moldura muda (decisão 3)

Casas do xadrez e das damas (`BOARD_LIGHT`, `BOARD_DARK`), tabuleiro do Ludo,
mesa da sinuca, mares da naval (`WATER`, `WATER_ALT`, `SPLASH`, `HULL`) e mapa do
Bomberman. As constantes de cor desses desenhos **não** entram na troca de
paleta da seção 3; o que muda é a borda externa, a sombra e o que é desenhado
por cima como interface (seleção, último lance, mira, rótulos de coordenada).

### Não entra neste trabalho

Tutorial jogável, dicas de primeira partida, recolorir tabuleiros, jogos novos,
mudanças de regra.

## 3. Sistema visual

### Cor

Todas as cores da interface saem de `ui/app_theme.gd`. Hoje são 175 usos em 45
arquivos, e mais 65 `Color("...")` soltos fora dele; os soltos que forem
**interface** passam a usar tokens, os que forem **conteúdo de jogo** (cor de
assento, cor de bola, cor de grupo de Metrópole) ficam onde estão.

| Token | Hex | Papel | Substitui |
| --- | --- | --- | --- |
| `BACKGROUND` | `#17211C` | lousa: fundo de toda tela | `13100E` |
| `SURFACE` | `#1F2B25` | tampo: painéis e folhas | `1E1A17` |
| `SURFACE_HIGH` | `#2A3931` | campos, segmentos inativos | `2A2421` |
| `COASTER` | `#0E1511` | fundo das bolachas e do placar | novo |
| `TEXT` | `#F1EDE3` | giz: texto principal | `F2EAE0` |
| `TEXT_DIM` | `#A4B0A7` | texto secundário (7,3:1 sobre a lousa) | `A2968A` |
| `LINE_SOFT` | `#F1EDE3` a 22% | tracejado decorativo | `BORDER` |
| `LINE` | `#F1EDE3` a 45% | contorno de coisa tocável (≥ 3:1) | `BORDER` |
| `ACCENT` | `#F2C029` | amarelo de cadeira de plástico: ação principal, vez | `D9A441` |
| `ACCENT_INK` | `#1C1A10` | texto sobre o amarelo (10:1) | novo |
| `ACCENT_SOFT` | `#F2C029` a 12% | fundo de "é a sua vez" | `ACCENT_SOFT` |
| `GOLD` | `#D9A441` | dourado do chopp: anel das bolachas | novo |
| `PAPER` | `#EFE7D4` | comanda, escritura, dado | novo |
| `PAPER_INK` | `#221C13` | texto sobre papel | novo |
| `DANGER` | `#E8694C` | sair, alarme (5,2:1) | `E05A4D` |
| `SUCCESS` | `#7EC27F` | mantém | `7EC27F` |

`LAST_MOVE` e `PREMOVE` continuam existindo com os valores de hoje: são
desenhados **sobre o tabuleiro**, e o tabuleiro não muda.

### Tipografia

Hoje o app usa `SystemFont` (Roboto/Segoe). O Boteco precisa de três famílias
**embarcadas** em `assets/fonts/`, todas SIL OFL 1.1 (licença vai junto do
arquivo):

| Papel | Família | Pesos | Uso |
| --- | --- | --- | --- |
| Display | Big Shoulders Display | 700, 900 | títulos, nomes de jogador, botões, "SUA VEZ" — sempre em maiúsculas |
| Corpo | Atkinson Hyperlegible | 400, 700 | texto corrido, legendas, descrições |
| Mono | IBM Plex Mono | 500, 600 | código da sala, relógio, dinheiro, lotação |

Atkinson Hyperlegible foi desenhada para leitura difícil — tela na mesa, longe do
rosto —, e é o motivo de o corpo não ser uma grotesca qualquer.

A assinatura continua `AppTheme.font(weight)` para quem já a chama, com o papel
como segundo argumento — `AppTheme.font(900, AppTheme.Role.DISPLAY)` — e os atalhos
`display()` e `mono()`. O cache por papel e peso continua (o motivo dele, desenhar
blocos no lugar de glifos, não mudou).

Escala, em pixels lógicos da base de 432 de largura:

| Nome | Família | Tamanho |
| --- | --- | --- |
| `DISPLAY_XL` | Display 900 | 34 |
| `DISPLAY_L` | Display 900 | 26 |
| `DISPLAY_M` | Display 900 | 20 |
| `BUTTON` | Display 900 | 19 (letras espaçadas 4%) |
| `BODY` | Corpo 400 | 16 |
| `BODY_S` | Corpo 400/700 | 14 |
| `CAPTION` | Corpo 700, maiúsculas | 12 |
| `MONO_L` | Mono 600 | 34 |
| `MONO_M` | Mono 600 | 22 |
| `MONO_S` | Mono 500 | 13 |

### Forma

- Raio padrão 10, raio de folha 16. Placa amarela (retomar, botão principal): raio
  6 com uma sombra dura de 3 px embaixo, como placa de plástico.
- **Tracejado** é a assinatura do tema e aparece em três lugares só: contorno de
  painel secundário, separador de lista e borda de folha. `StyleBoxFlat` não
  desenha tracejado; entra um `StyleBoxDashed` próprio (um `StyleBox` com
  `_draw` usando `draw_dashed_line`), reaproveitável por qualquer `Control`.
- **Bolacha** é o avatar de jogador: círculo `COASTER` com a inicial, anel `GOLD`
  (ou na cor do assento dentro da partida) e um anel `ACCENT` quando é a vez.
- **Papel** (`PAPER` + `PAPER_INK`, raio 3, levemente girado) só em três
  objetos: a comanda do código da sala, a escritura de Metrópole e o dado.
- Sombra só no que flutua sobre a mesa (tabuleiros, folhas, papel).

### Movimento

Mantém os tempos de hoje (entrada de tela 0,16 s). Novo: a folha sobe em 0,22 s
com desaceleração; o anel de vez pulsa uma vez ao trocar de jogador. Tudo
desligado quando o sistema pede menos movimento.

## 4. Componentes

Todos em `ui/`, compostos por nós, um arquivo por componente (preferência do
projeto por cenas pequenas reutilizáveis sobre scripts monolíticos).

| Componente | Novo/Muda | Faz |
| --- | --- | --- |
| `AppTheme` | muda | tokens da seção 3, fontes embarcadas, variações `Display`, `Title`, `Caption`, `Mono`, botões `PrimaryButton` (placa), `GhostButton` (tracejado), `DangerButton` |
| `StyleBoxDashed` | novo | contorno tracejado com raio |
| `Coaster` | novo | bolacha: inicial, cor, anel de vez, tamanho |
| `PaperCard` | novo | contêiner de papel (comanda, escritura) |
| `TabBar` | novo | abas Jogos · Online · Você na base; substitui `NavDrawer` e a engrenagem do `AppBar` |
| `AppBar` | muda | logo + "Olá, Nome" + bolacha do jogador |
| `ResumeCard` | muda | vira placa amarela |
| `CatalogMenu` | novo | lista do catálogo como cardápio de lousa: peça, nome, pontilhado, lotação |
| `GameChoice` | muda | cartão de favorito com a peça dentro de uma bolacha |
| `GameSheet` | novo | folha do jogo (seção 6.2); substitui `scenes/game_menu.tscn` e o diálogo de ajustes |
| `SegmentedControl` | novo | abas de modo e de formato |
| `CodeInput` | novo | seis casas de papel; colar preenche tudo; entra sozinho no sexto caractere |
| `RoomCard` | muda | peça em bolacha, lotação em bolinhas |
| `SeatTable` | novo | mesa redonda com até 6 bolachas em volta |
| `MatchBar` | novo | barra de partida: sair · título e meta · `?` · menu. Absorve `LeaveButton` (a confirmação de sair continua) e `MatchStatus` (tempo, rodadas, código com copiar) |
| `PlayerTag` | novo | bolacha + nome + detalhe + marca "sua vez"; variantes faixa (em pé) e etiqueta ancorada (deitado) |
| `DieView` | muda | dado de papel |
| `Banner` / toast | muda | fundo `COASTER`, borda tracejada na cor do tipo |
| `RulesPage` | novo | página de Como jogar (seção 7) |
| `TableRulesDrawer` | novo | gaveta "Regras desta mesa" (seção 7) |

`ChipBar` (o menu suspenso de filtro) continua como componente — o pedido de
trocar a barra arrastável por menu suspenso vale — e só troca de pele.

## 5. Mudanças de uso

1. **Abas na base** — Jogos · Online · Você. A gaveta e a engrenagem saem. O
   gesto de voltar do Android numa aba que não seja Jogos leva a Jogos; em Jogos,
   mantém o comportamento de hoje.
2. **Escolher o modo numa folha só** — ver 6.2.
3. **Código em seis casas** — ver 6.3.
4. **Sala de espera com cadeiras** — ver 6.4.
5. **Um painel de partida para todos os jogos** — `MatchBar` no topo e cada
   jogador preso ao lugar dele na mesa.
6. **A instrução perto da mão** — o texto de status fica colado aos botões de
   ação, e não numa coluna distante.

## 6. Telas

### 6.1 Início (aba Jogos)

`AppBar` → `ResumeCard` (se houver partida para voltar) → Favoritos (dois
`GameChoice` grandes lado a lado; some quando não há favorito) → "Todos os jogos"
com `ChipBar` à direita → `CatalogMenu` → `TabBar`. Tocar num jogo abre a
`GameSheet` por cima. A estrela de favorito continua no cartão e aparece também no
fim de cada linha do cardápio, depois da lotação — visível, e não escondida num
toque longo.

### 6.2 Folha do jogo (`GameSheet`)

Sobe por cima do Início. Cabeçalho: peça em bolacha, nome, lotação e categoria,
link **Como jogar**. Abaixo:

- `SegmentedControl` com os modos disponíveis do catálogo, **na ordem Online ·
  Neste aparelho · Contra bot** e só os que o jogo tem (Uno: Online · Contra bots;
  Naval: só Online, sem abas).
- Os ajustes do modo escolhido, os mesmos de hoje: ritmo (xadrez e damas),
  jogadores (Uno e Metrópole), formato (Uno, Sinuca), limite de rodadas
  (Metrópole), nível do bot, lado (contra bot), "aparecer na lista de salas"
  (online).
- Um botão: **Criar sala** (online) ou **Começar**.

Fechar: arrastar para baixo, tocar fora, ou o gesto de voltar.

### 6.3 Online (aba Online)

Título "Online" → cartão tracejado com `CodeInput`, "Ler QR" e "Entrar" → botão
"Criar sala" (abre o seletor de jogo e em seguida a `GameSheet` já em Online) →
"Salas abertas" com `ChipBar` → lista de `RoomCard` → `ResumeCard` no topo quando
houver partida para voltar. O NFC continua ligado enquanto a aba está aberta, com
a mesma frase de hoje.

### 6.4 Sala de espera

**Anfitrião:** comanda de papel com o código grande, "Copiar" e "Mostrar QR" (o
QR abre numa folha; hoje ocupa meia tela fixo) → "Na mesa · 2 de 4" →
`SeatTable` → dica curta → "Começar com N bots" quando couber (mesma regra de
hoje).

**Convidado** (`WaitingPanel`): a mesma `SeatTable`, com o nome do jogo e o código.

### 6.5 Você (aba Você)

Os ajustes de hoje: nome, som, vibração, "sobre este build". O nome abre o mesmo
campo das boas-vindas.

### 6.6 Boas-vindas

Folha de papel sobre o Início esmaecido: "Oi! Como te chamamos?", campo, "Bora
jogar".

### 6.7 Partidas em pé

**Xadrez e damas** — `MatchBar` → `PlayerTag` do adversário (capturas, relógio em
placar `COASTER` com dígitos amarelos) → tabuleiro com moldura nova → último lance
→ `PlayerTag` local (acende amarelo na vez) → status. **Modo mesa** (dois
jogadores num aparelho): a faixa de cima continua girada 180°, como hoje.

**Batalha Naval, posicionar frota** — mesma estrutura de hoje, com a lista de
navios em faixa tracejada e o botão principal em placa.

**Batalha Naval, partida** — `MatchBar` → `PlayerTag` do adversário → mar dele
grande → embaixo, o seu mar pequeno ao lado da sua `PlayerTag` e do status. O
balão do último tiro vira uma etiqueta `COASTER` com borda amarela.

### 6.8 Partidas deitadas

Todas com `MatchBar` de 42 px e o jogo ocupando o resto.

- **Uno** — cada `PlayerTag` ancorada à pilha do próprio jogador (substitui a
  coluna da esquerda); a local no canto inferior esquerdo; status e os botões
  de hoje (Comprar N, Duvidar, UNO!, Pegar Fulano, Passar) no canto inferior
  direito, ao lado do leque; comprar do monte continua sendo tocar no monte. As escolhas de cor e de alvo do 7 viram folha de papel.
- **Ludo** — `PlayerTag` ao lado do canto do tabuleiro que é da cor do jogador,
  com os peões que já chegaram em casa em bolinhas; dado de papel com a
  instrução do lado, na coluna direita.
- **Metrópole** — tabuleiro 3D em tela cheia; `MatchBar` translúcida; coluna de
  jogadores flutuante com dinheiro em mono amarelo e "Trocar"; a casa escolhida
  vira escritura de papel (faixa na cor do grupo, tabela de aluguel com o valor
  atual marcado, Construir/Vender); dados de papel com "Rolar". A mesa de troca e
  o resultado final seguem o mesmo vocabulário.
- **Sinuca** — duas `PlayerTag` na coluna esquerda com a cor das próprias bolas e
  quantas do adversário faltam; status embaixo; mesa à direita.
- **Bomberman** — quem está de pé em lista no canto superior esquerdo;
  direcional em bolacha grande embaixo à esquerda; botão de bomba amarelo
  embaixo à direita; "N de pé" em cima à direita. O lobby do Bomberman segue a
  sala de espera (6.4).

### 6.9 Fim de partida e revanche

Folha de papel central: resultado em Display, subtítulo, "Revanche" (placa) e
"Sair" (tracejado). A negociação de revanche em rede (pedido, aceite, recusa)
continua igual.

## 7. Como jogar

### Duas portas, uma fonte

- **Pela folha do jogo** (link "Como jogar") abre a `RulesPage` completa, com
  `SegmentedControl` de formato quando o jogo tem mais de um (Sinuca: Mata-mata ·
  Brasileira).
- **Pelo `?` da `MatchBar`** abre a `TableRulesDrawer`: só as regras **desta
  mesa**, cada uma com o estado (ligada, sempre, valor) e um link para a página
  completa.

### Onde o conteúdo mora

Um `Resource` por jogo, `GameRulesDoc`, em `data/rules/<jogo>.tres` — dado
editável no inspetor, sem texto de regra dentro de cena. Campos: `objective`,
`steps` (lista curta, é sequência de verdade e por isso numerada), `notes`
(faltas, empates, avisos), `diagram` (identificador de um desenho simples feito
em código, opcional) e `formats` (um bloco por formato, quando houver).

As regras **desta mesa** não moram no `.tres`: elas dependem das opções da
partida. Uma função por jogo em `ui/rules/table_rules.gd` monta a lista a partir
do que a cena já sabe (`Game`, `Net.option`, o ruleset), por exemplo:

| Jogo | Regras desta mesa |
| --- | --- |
| Uno | 0 e 7 (ligada/desligada), empilhar +2/+4, duvidar do +4 (+2 de multa), gritar UNO (2 cartas) |
| Sinuca | formato; no mata-mata, "falta passa a vez"; na brasileira, a multa de 7 |
| Metrópole | limite de rodadas |
| Xadrez / damas | ritmo |
| Ludo, Naval, Bomberman | as regras fixas mais importantes |

`core/` continua sem conhecer `ui/`: o texto é apresentação e mora fora dele; os
números (multas, valores) são lidos das constantes das regras, para o texto não
desatualizar quando uma regra mudar.

### Conteúdo

Escrito a partir do código de regras de cada jogo, não de memória — o redesenho
não muda regra nenhuma, e a página não pode descrever outra. Os oito jogos:
Xadrez (inclui roque, en passant, promoção e o premove em cadeia do app), Damas,
Batalha Naval, Ludo, Metrópole, Uno, Sinuca (os dois formatos) e Bomberman.

## 8. Plano de implementação (ordem)

Cada etapa termina com as suítes verdes, a folha de prints refeita e um commit.

1. **Fundação** — fontes embarcadas, `AppTheme` novo, `StyleBoxDashed`, `Coaster`,
   `PaperCard`, `SegmentedControl`. Folha de prints atualizada para as telas novas.
2. **Navegação e menus** — `TabBar`, Início, `GameSheet`, Online (`CodeInput`,
   salas), sala de espera (`SeatTable`), Você, boas-vindas.
3. **Partidas em pé** — `MatchBar`, `PlayerTag`, xadrez e damas (com modo mesa),
   naval (frota e partida), fim de partida.
4. **Partidas deitadas** — Uno, Ludo, Sinuca, Metrópole (painéis, troca, fim),
   Bomberman (partida e lobby).
5. **Como jogar** — `GameRulesDoc`, oito `.tres`, `RulesPage`,
   `TableRulesDrawer`, `?` em todas as `MatchBar`.
6. **Limpeza** — remover o que ficou órfão (`NavDrawer`, `LeaveButton` e
   `MatchStatus` se absorvidos), README, prints finais.

## 9. Verificação

- Suítes atuais verdes a cada etapa. As probes de cena que procuram nós pelo
  nome (`pairing_probe`, `scene_probe`, `uno_scene_probe`, `pool_scene_probe`,
  `ludo_probe`) vão quebrar nas etapas 2–4 **por mudança de estrutura, não de
  comportamento**; elas são atualizadas na mesma etapa, e o que elas provam
  (favorito conta uma vez, voltar à partida, toque no leque, vez do bot…) continua
  sendo provado.
- Probe nova de Como jogar: todo jogo visível do catálogo tem `GameRulesDoc` com
  objetivo e passos; as regras desta mesa do Uno refletem o 0 e 7 da opção; as da
  Sinuca refletem o formato.
- Folha de prints (`tests/screen_sheet.gd`) cobre todas as telas da seção 6 nas
  proporções de celular (432×768 em pé, 1560×720 deitado), e a comparação com os
  conceitos aprovados é feita por print, etapa a etapa.
- Contraste: os pares da tabela de cor ficam em ≥ 4,5:1 para texto e ≥ 3:1 para
  contorno de coisa tocável.

## 10. Riscos

- **Tamanho do APK**: três famílias embarcadas somam algumas centenas de KB —
  aceitável; só os pesos listados entram.
- **Tracejado em listas longas**: `draw_dashed_line` por item redesenha a cada
  quadro que o item redesenhar; a lista de salas e o cardápio têm poucos itens,
  mas vale conferir no aparelho.
- **Modo mesa do xadrez**: a faixa girada precisa continuar legível com a tag
  nova.
- **Seis jogadores** no Uno e em Metrópole: as `PlayerTag` ancoradas precisam de
  posição para seis, e é onde o layout aperta.
- **Baixar as fontes** é um passo que pede sua autorização no início da etapa 1
  (arquivos do repositório oficial `google/fonts`, licença OFL).

## 11. Ferramenta de rascunho

`tests/redesign_assets.gd` exporta cartas e tabuleiros sem o fundo para os
conceitos e para as comparações de imagem. Ficou versionada: ela é a ferramenta
que prova, a cada etapa, que o desenho protegido não mudou.
