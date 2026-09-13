# Bomberman: migração de lockstep para servidor autoritativo + predição

Plano para trocar a rede do Bomberman do modelo **lockstep P2P via relay** para o
modelo do streetVolley: **servidor Godot autoritativo + predição no cliente com
reconciliação**. Objetivo: matar o input delay fixo de 167 ms e as travadas
quando um peer engasga.

## Progresso

- [x] **Etapa 1** — protocolo + serialização (`core/bomber_protocol.gd`,
  `to_bytes`/`from_bytes` em `core/bomber_state.gd`). Verde:
  `tests/bomber_snapshot_probe.gd`. Snapshot cheio = 532 bytes.
- [x] **Etapa 2** — sala autoritativa (`net/bomber_room.gd`). Verde:
  `tests/bomber_room_probe.gd`.
- [x] **Etapa 3** — predictor com convergência exata (`net/bomber_predictor.gd`).
  Verde: `tests/bomber_predict_probe.gd`.
- [x] **Etapa 4** — transporte ENet + servidor headless (`autoload/bomber_net.gd`,
  `server/main.gd` + `.tscn`, autoload `BomberNet` em `project.godot`). Verde:
  `tests/bomber_net_smoke.gd` (server bg + cliente).
- [x] **Etapa 5, parte 1** — reescrita de `scenes/bomber_match.gd` (lockstep →
  predição + snapshots + paced step). Regressão offline verde:
  `tests/bomber_match_offline_probe.gd`.
- [x] **Etapa 5, parte 2** — lobby próprio do bomberman:
  - `scenes/bomber_lobby.gd` + `.tscn` (anfitrião: cria sala, mostra QR/NFC, botão
    começar; convidado: entra e espera). Reaproveita `QrCodeView`, `Pairing.nfc`,
    `Pairing.build_payload`, `Banner` como `scenes/pairing.gd`. `BomberNet` ganhou
    `pending_code` (vazio = criar, com código = entrar).
  - `scenes/game_menu.gd` (`_open_pairing`): bomberman ONLINE anfitrião →
    `bomber_lobby`.
  - `ui/join_panel.gd` (`_enter_room`): `id == BOMBERMAN` → `BomberNet` +
    `bomber_lobby` convidado.
  - Parse limpo; todos os probes verdes; net smoke ponta a ponta verde.

## O que falta pra jogar

1. **Deploy** (etapa 6, ação do dono): `fly apps create bomber && fly deploy &&
   fly scale count 1`.
2. **Teste no aparelho**: dois celulares, um cria (QR/NFC), o outro lê, anfitrião
   começa. Conferir sensação (input local instantâneo, sem travadas) e rubber-band
   de adversários/bombas.
3. **Etapa 7 — limpeza** (só depois de 2 confirmar): remover
   `core/bomber_lockstep.gd` e os testes `_test_lockstep*` de `bomber_probe.gd`.
   Deixado no lugar de propósito até o modelo novo estar provado no aparelho — o
   offline usa simulação direta, não o lockstep, então ele já está órfão, mas
   removê-lo agora não ganha nada e perde a rede de segurança.
- [~] **Etapa 6** — deploy Fly. Arquivos prontos: `Dockerfile`, `fly.toml`
  (app `bomber`, UDP 27016, `BOMBER_BIND=fly-global-services`, count 1),
  `.dockerignore`. Falta a subida (ação do dono da conta):
  `fly apps create bomber && fly deploy && fly scale count 1`. `SERVER_HOST` já
  aponta pra `bomber.fly.dev`.
- [ ] **Etapa 7** — limpeza do lockstep (`core/bomber_lockstep.gd` + testes que só
  dependem dele).

## Reformulação do lobby (QR/NFC preservado)

O QR/NFC **não muda**. O payload já é só `XDM3|game|código` (`autoload/pairing.gd`)
— nunca carregou IP/porta (saiu na v5). É um canal de código, agnóstico de
transporte. A única mudança é pra onde o código conecta:

- Antes: código → sala no relay.
- Agora (só bomberman): código → sala no servidor ENet (`SERVER_HOST` fixo).

Fluxo: anfitrião conecta → `ask_room("")` → servidor devolve código → mostra
QR/NFC com `Pairing.build_payload("bomberman", code)`; convidado lê → conecta →
`ask_room(code)`. Lobby (seats/nomes/começar) vive no servidor, como no volei, mas
só pro bomberman. Semente não viaja: o primeiro snapshot já traz mapa+semente.

O anfitrião tem um **start explícito** (o volei auto-inicia): a mesa de grade
precisa esperar os amigos lerem o QR antes de começar.

## Diagnóstico (por que hoje laga)

Lockstep tem dois custos inerentes, ambos em `core/bomber_lockstep.gd`:

1. **Input delay fixo de 167 ms** (`DELAY = 5` tiques a 30 Hz). O próprio boneco
   e a própria bomba sempre saem 5 tiques depois do dedo. É de projeto, não é
   rede.
2. **A simulação para quando falta o byte de qualquer peer** (`ready_for`). Com 4
   jogadores em rede móvel + relay, alguém engasga com frequência e **todos**
   param juntos. O relay ainda soma latência e tem teto de 40 msg/s.

O volei não sofre porque o servidor é autoritativo e nunca para (repete o último
comando conhecido), e o cliente prevê o próprio boneco na hora e reconcilia
depois (`net/predictor.gd`, `net/room.gd` do streetVolley).

## Decisão de modelo (já tomada)

**Modelo volei completo**, adaptado para grade:

- **Assento local**: aplica o próprio comando no tique em que ele acontece. Zero
  input delay sentido.
- **Humanos remotos**: repete-último para o **movimento**, mas **zera o bit de
  bomba** (`IN_BOMB`) nos tiques ainda não confirmados. Bomba de outro só aparece
  quando o servidor confirma o comando. Isto é o cerne da adaptação: repetir o
  comando cru plantaria uma bomba-fantasma a cada tique.
- **Bots**: rodam `BomberBot` localmente. Determinístico e sem `randi()`, então a
  decisão local bate com a do servidor — mesma propriedade que o volei usa.
- **Reconciliação**: o servidor devolve os comandos que **de fato usou**; o
  cliente volta ao snapshot e refaz o intervalo com a verdade. O erro fica
  confinado aos poucos tiques mais novos que ainda não chegaram.

Trade aceito: o boneco local é perfeito e as travadas somem; trocas de direção de
adversários e bombas alheias podem corrigir na tela com o ping deles.

## Arquitetura alvo

O chessAndCheckers tem 6 jogos; só o Bomberman é tempo real. Os outros 5
continuam no relay WebSocket (turn-based). O servidor autoritativo entra **ao
lado** do relay, não no lugar:

- 5 jogos por turno → relay WebSocket existente (`net_link.gd`, `relay/`).
- Bomberman → servidor Godot headless via ENet UDP (novo).

O cliente passa a falar dois transportes. **Não entrelaçar**: a rede do bomber
vive num módulo próprio, independente de `net_link.gd`.

Por que ENet UDP direto funciona aqui, sendo que o P2P morreu de NAT: o servidor
é dedicado e os clientes **discam pra fora**, então o NAT deixa de importar — é
exatamente o que o comentário de `streetVolley/autoload/net.gd:10-19` documenta.

## Pré-requisito: determinismo (já garantido)

`BomberRules` é determinística e o RNG é `state.seed_state` (`next_random`), que
viaja no snapshot. Predição/replay avançam o `seed_state` de forma determinística.
RNG só é consumido em eventos raros (queda de caixa → sorteio de prêmio), então a
predição quase nunca o toca. Nada a mudar nas regras.

## Componentes (espelhando o streetVolley)

Templates entre parênteses.

1. **`core/bomber_protocol.gd`** — números e formato binário, um lugar só.
   (template: `streetVolley/net/protocol.gd`)
   - `SERVER_HOST`, `PORT`, `VERSION`, `SNAPSHOT_HZ` (~20), `FRAME` (2),
     `HISTORY` (4), `INPUT_GRACE` (~12).
   - `write_inputs` / `read_inputs`: comando é **1 byte por tique** (mais simples
     que o volei, que empacota `VolleyCommand`).
   - `write_frame` / `read_frame`: linhas de `seats` bytes — o que o servidor usou.
   - Código de sala: reaproveitar o esquema do relay ou o alfabeto do volei.

2. **`core/bomber_snapshot.gd`** (ou métodos em `BomberState`) —
   `to_bytes()` / `from_bytes()` / `empty()`.
   (template: `streetVolley/core/volley_state.gd:286-376`)
   - v1: snapshot **completo** por simplicidade e correção. Campos: `tick`,
     `seats`, `seed_state`, `players[]` (x, y, facing, alive, died_at, bombs,
     flame, speed), `bombs[]` (col, row, owner, fuse, flame, pass_seats),
     `tiles[143]`, `prizes[143]`, `flames[143]`.
   - Tamanho ~400–500 bytes; a 20 Hz ~10 kB/s por cliente. Aceitável.
   - Otimização futura (só com evidência): `tiles`/`prizes` mudam raro — mandar
     mapa só no primeiro snapshot e diferencial depois. **Não** fazer na v1.

3. **`net/bomber_room.gd`** — sala autoritativa no servidor.
   (template: `streetVolley/net/room.gd`)
   - Gera o mapa (`initial_state(seats, seed)`) — o **servidor** decide a semente,
     não o cliente. Mata todo o caminho "semente pelo welcome".
   - Assento vazio = bot, calculado no servidor. **Elimina** toda a máquina de
     `DROP`/`RELAY`/`bot_driver`/`bot_seats` do lockstep: quem sai vira assento
     vazio e o servidor joga como bot.
   - `receive` (caixa de entrada por assento, com `INPUT_GRACE`), `step`
     (comando conhecido, senão repete último, senão bot), `recent_commands`.

4. **`autoload/bomber_net.gd`** — o fio ENet, mesmo arquivo dos dois lados.
   (template: `streetVolley/autoload/net.gd`)
   - `start_server` (com `BIND_ENV` para Fly), loop de passo fixo 30 Hz +
     snapshots 20 Hz, RPCs de sala (`ask_room`, `take_seat`, `start`,
     `send_inputs`), canais ENet: 0 confiável (sala), 1 comandos (não confiável +
     histórico), 2 snapshots (não confiável, sem ordem).

5. **`net/bomber_predictor.gd`** — predição/reconciliação no cliente.
   (template: `streetVolley/net/predictor.gd`)
   - `adopt`, `advance(local_command)`, `note(first_tick, rows)`,
     `reconcile(snapshot)`, janela `MEMORY`.
   - `_command_for`: local = próprio; remoto conhecido = verdade; remoto
     desconhecido = repete-último **com `IN_BOMB` zerado**; bot = `BomberBot`.
   - Guarda `previous` durante o replay para a tela interpolar sem estalo.

6. **`server/main.gd` + `server/main.tscn`** — servidor headless.
   (template: `streetVolley/server/main.gd`)
   - Abre a porta via `BomberNet.start_server`, imprime estado, sai da frente.

7. **Reescrever `scenes/bomber_match.gd`** — o loop.
   - Fora: `BomberLockstep`, `_input_tick`, `_stalled`, `_run_input_clock`,
     `_run_simulation` no formato atual, `DROP`/`RELAY`/`_on_seat_left`/
     `_apply_drop`/`bot_driver`.
   - Dentro: predição local por tique (`predictor.advance(_local_input())`),
     `adopt` no primeiro snapshot, `reconcile` nos seguintes, `note` nos frames.
   - Fim de partida: autoritativo — derivar de `BomberRules.winner` sobre o estado
     adotado, ou RPC confiável de fim.
   - Render: `BomberView` já interpola `previous → state`; alimentar do predictor.

8. **Deploy** — `Dockerfile` + `fly.toml` do servidor bomber.
   (template: `streetVolley/Dockerfile`, `streetVolley/fly.toml`)
   - `CMD godot --headless --path /app res://server/main.tscn`
   - `fly.toml`: `[[services]] protocol='udp'`, `internal_port` = porta, bind em
     `fly-global-services` (pegadinha do Fly, ver comentários do volei).
   - App Fly separado do relay.

9. **Limpeza (depois de validar)** — remover `core/bomber_lockstep.gd` e os testes
   que dependem só dele.

## Ordem de implementação

1. `bomber_protocol.gd` + serialização (`to_bytes`/`from_bytes`) — base testável
   sozinha, sem rede.
2. `bomber_room.gd` — testável headless sem socket (alimenta comandos, roda
   `step`, confere `state.tick`).
3. `bomber_predictor.gd` — testável sem rede: alimentar snapshots atrasados e
   provar convergência.
4. `bomber_net.gd` + `server/main.*` — junta tudo no cano ENet.
5. Reescrita de `bomber_match.gd`.
6. `Dockerfile`/`fly.toml` + subir servidor.
7. Limpeza do lockstep.

Cada etapa é verde antes da próxima.

## Critérios de aceite

**Serialização (etapa 1)**
- `from_bytes(to_bytes(s))` reproduz o estado campo a campo, incluindo
  `seed_state`, `bombs` e os três mapas de 143 bytes.
- Snapshot de partida cheia (4 jogadores, várias bombas) cabe no limite de pacote
  ENet e mede < ~600 bytes.

**Sala autoritativa (etapa 2)**
- Servidor headless: o tique anda ~30/s.
- Comando que chega dentro de `INPUT_GRACE` é aplicado no tique certo; mais velho
  é descartado (não reescreve o passado).
- Byte faltante não trava: `step` repete o último comando do assento.
- Assento vazio joga como bot; sem `randi()`, dois servidores com a mesma semente
  produzem a mesma partida.

**Predição (etapa 3)** — o teste central
- Partindo de um snapshot no tique T e comandos verdadeiros até T+N, o predictor
  reexecutado converge **exatamente** para o mesmo estado que `BomberRules`
  rodada direta produz (posição de todos, bombas, mapa, `seed_state`).
- Reconciliação com snapshot atrasado: `drift` do próprio boneco = 0 (o dedo
  local nunca é chute).
- Bomba de remoto **não** aparece em tique previsto sem confirmação; aparece no
  tique correto quando o frame confirma.
- Repete-último de remoto nunca planta bomba-fantasma.

**Cano de rede (etapa 4)** — `tests/bomber_net_smoke.gd`
- Conectar, criar/entrar em sala, mandar comando, receber snapshot; o tique do
  servidor anda (mesmo padrão do `streetVolley/tests/net_smoke.gd`).

**Ponta a ponta (etapa 5)**
- Com 2 clientes headless na mesma sala, o estado converge entre eles em regime
  (mesmo `tick` recente → mesmas posições, tolerância de interpolação).
- Latência simulada de 150 ms: o boneco local responde no mesmo tique; sem
  travadas globais.

**Deploy (etapa 6)**
- Servidor no Fly recebe pacotes UDP (o bind em `fly-global-services` é o ponto
  que costuma falhar em silêncio).
- Cliente release conecta pelo `SERVER_HOST` e joga uma partida completa.

## Testes a criar/adaptar

- `tests/bomber_snapshot_probe.gd` — round-trip de serialização (novo).
- `tests/bomber_room_probe.gd` — sala headless: passo, grace, bot em vazio (novo,
  adaptar de `bomber_probe.gd`).
- `tests/bomber_predict_probe.gd` — convergência do predictor, o teste mais
  importante (novo).
- `tests/bomber_net_smoke.gd` — reescrever para ENet (hoje é do relay), template
  `streetVolley/tests/net_smoke.gd`.
- Manter `bomber_bot_trace.gd` (determinismo do bot) — a predição depende dele.

## Riscos e pontos de atenção

- **Bomba-fantasma na predição de remotos** — resolvido zerando `IN_BOMB` no
  repete-último. É o erro mais fácil de cometer nesta migração.
- **Custo do snapshot** — bomberman é mais pesado que o volei (mapa + bombas
  variáveis). v1 manda cheio; medir antes de otimizar.
- **Dois transportes no cliente** — não deixar a rede do bomber vazar em
  `net_link.gd`. Módulo isolado.
- **Fim de partida autoritativo** — a decisão de quem venceu passa a ser do
  servidor; o cliente para de decidir localmente.
- **Fly + UDP** — o bind em `fly-global-services` é obrigatório; no coringa o
  socket abre e nenhum pacote chega.
- **Sensação em grade** — se o rubber-band de adversários incomodar, o passo
  seguinte é absorver a correção em alguns quadros (como o `correction` em
  micrômetros do `predictor.gd` do volei), não voltar pro lockstep.
