# Relay de partidas

Servidor WebSocket que liga de dois a seis aparelhos em **redes diferentes** —
um no Wi-Fi de casa, o outro no 4G, cada um atrás do seu NAT. É o único
componente do jogo que precisa de endereço público.

Sem ele o jogo continua funcionando lado a lado (Nearby) e na mesma rede
(ENet), que é o que o app fazia antes.

## Por que relay e não P2P

WebRTC daria conexão direta, mas exigiria mesmo assim um servidor de
sinalização, mais STUN, mais um TURN de reserva — e em rede móvel uma fatia
grande das conexões acaba caindo no TURN, que é um relay com mais etapas. Um
lance de xadrez tem ~40 bytes e o jogo é por turnos: latência e banda são
irrelevantes aqui. O relay direto é menos código e conecta em 100% dos casos.

## O que o servidor sabe

Nada sobre xadrez. Ele mantém `código da sala → N sockets` e repassa bytes. As
mensagens de jogo viajam opacas dentro de `{"t":"msg","d":…}`; o servidor nunca
abre `d`.

Isso não é só elegância: os clientes rodam o mesmo ruleset determinístico e
validam cada lance recebido contra a própria lista de lances legais
(`scenes/match.gd:_on_remote_move`). Um relay comprometido não consegue forjar
uma partida — no máximo derrubá-la.

## Protocolo

Além do WebSocket, dois endpoints HTTP:

| Rota | Devolve |
|---|---|
| `GET /healthz` | `{ok, rooms, machine}` — `machine` denuncia mais de um processo |
| `GET /rooms` | `{rooms:[{code, game, tc, age, seats, taken}]}` — só as salas públicas com vaga |

`/rooms` filtra: sala sem ninguém conectado, ou já cheia, não entra. Anunciar
uma sala lotada só renderia um `room_full` para quem tocasse nela. `seats` é a
capacidade e `taken` a ocupação — é o que deixa a lista dizer "2 de 4 jogadores"
numa mesa que ainda precisa de gente.

Cliente → servidor:

| Mensagem | Quando |
|---|---|
| `{"t":"host","room":"ABC123","game":"chess","listed":false,"tc":0,"seats":2}` | abre a sala e senta no assento 0 |
| `{"t":"join","room":"ABC123","key":""}` | entra; com `key`, volta ao assento que era dele |
| `{"t":"msg","d":{…}}` | qualquer mensagem de jogo |
| `{"t":"ping"}` | keepalive do cliente |
| `{"t":"leave"}` | saída limpa |

Servidor → cliente:

| Mensagem | Significado |
|---|---|
| `{"t":"joined","seat":0,"game":"chess","seats":2,"present":[0],"key":"a1b2c3d4"}` | assento confirmado, com a mesa inteira e a chave de volta |
| `{"t":"peer","seat":1}` | alguém chegou (ou voltou) naquele assento |
| `{"t":"peer_left","seat":1}` | aquele assento vagou |
| `{"t":"msg","d":{…},"from":1}` | repasse, assinado por quem falou |
| `{"t":"pong"}` | resposta ao ping |
| `{"t":"error","reason":"room_not_found","detail":"…"}` | erro, seguido de fechamento |

Razões de erro: `bad_code`, `bad_seats`, `room_taken`, `room_not_found`,
`room_full`, `hello_timeout`, `rate_limited`, `not_in_room`.

`listed` é opcional e o padrão é **falso**: uma sala só aparece em `/rooms`
quando quem a abriu pediu. Um cliente que não conhece o campo abre partida
privada, que é o que ele já esperava. `tc` é o índice do ritmo do lado do jogo —
o servidor só o guarda e repassa, sem saber o que significa.

## N assentos

A sala tem de 2 a 6 lugares, escolhidos por quem abre (`seats`). Eram dois, com
nome de papel (`host`/`guest`), e isso bastava enquanto todo jogo do catálogo
tinha dois jogadores — o Ludo tem quatro, e um par de nomes não cresce:
"guest2" e "guest3" seriam papéis inventados para dizer "o segundo" e "o
terceiro", que é o que um índice já diz.

O assento 0 é quem abriu. Ele continua tendo o papel especial do lado do jogo
(é quem manda o `welcome`), mas para o servidor é só o primeiro índice.

`seats` ausente vale 2, e `key` ausente vale primeira entrada: é o que um
cliente escrito antes do Ludo quis dizer, e continua querendo.

## Reconexão

A sala **não** é destruída quando todo mundo cai. Ela fica viva por
`ROOM_GRACE_MS` (90s), e quem reconecta com o mesmo código reocupa o assento que
era dele. É isso que faz a partida sobreviver à troca de Wi-Fi para 4G, ao
elevador e à tela bloqueada.

**A chave do assento** é o que torna isso correto com mais de dois jogadores.
Com dois lugares, "voltar para o seu" era trivial: só havia um livre. Com
quatro, dois jogadores caídos deixam dois buracos, e sem a chave o primeiro a
voltar senta no lugar do outro — e passa a jogar com os peões dele. Por isso o
`joined` traz uma `key` e o `join` da reconexão a devolve. Ela não protege a
sala (o segredo da sala é o código); ela responde **qual assento era o meu**.

O assento só é recusado quando já existe um socket **aberto** nele — um
`room_taken` significa mesmo colisão de código, não reconexão. Com chave na mão,
nem isso: a chave manda, porque o que está no assento é o socket zumbi da
conexão anterior.

Ping/pong em dois níveis: `ws.ping` do servidor a cada 25s (derruba socket
zumbi, que em rede móvel não fecha sozinho) e `{"t":"ping"}` do cliente, que é
o que faz o Godot perceber que o link morreu.

## Rodando local

```bash
cd relay && npm install && npm start
```

Aponte o jogo para ele com a variável de ambiente, no editor ou no dispositivo:

```bash
CHESS_RELAY_URL=ws://192.168.0.10:8080/ws godot --path .
```

Use o IP da máquina na rede, não `localhost` — o celular precisa alcançá-lo.

## Deploy

O relay roda no servidor de casa (a Raspberry Pi das contas), como o serviço
`relay` de `pocketbase/docker-compose.yml`, e sai para a internet pelo túnel do
Cloudflare (serviço `tunnel` do mesmo compose):

    wss://relay.cascapp.com.br/ws

Para publicar uma versão nova:

```bash
tools/deploy_relay.sh
```

O script copia `relay/` para `~/cascapp-relay` na Pi, constrói a imagem lá e
recria o container. Reiniciar derruba as salas em curso; os apps reconectam.

**Por que o túnel do Cloudflare, e não o Tailscale Funnel das contas:** o
ingresso do Funnel fica em Nova York. Medido em 2026-11-21 com
`latency-probe.mjs`, um lance levava 284 ms pelo Funnel, contra 14 ms no Fly em
`gru`. A borda do Cloudflare fica em São Paulo. A casa está em CGNAT, então
abrir porta no roteador não é opção.

O hostname público (`relay.cascapp.com.br` → `http://relay:8080`) fica no painel
do Cloudflare, em Zero Trust › Networks › Tunnels. O token do túnel mora no
`.env` das contas na Pi (`CLOUDFLARE_TUNNEL_TOKEN`), fora do repositório.

**Um container só, nunca réplicas.** As salas moram na memória do processo: com
dois processos atrás do mesmo endereço, anfitrião e convidado caem em processos
diferentes e nunca se acham. O jogador vê "nenhuma partida com esse código", que
parece erro de digitação. Para conferir, com uma partida aberta:

```bash
curl https://relay.cascapp.com.br/healthz
```

O campo `machine` tem de ser sempre o mesmo e `rooms` tem de ficar estável.

Até a 1.56 o relay rodava no Fly (`chess-checkers-relay.fly.dev`). As versões
antigas do app têm esse endereço fixo; a atualização obrigatória leva todo mundo
para o endereço novo.

## Escala

Uma sala = dois sockets ociosos trocando ~40 bytes por lance. Uma instância
`shared-cpu-1x` de 256MB aguenta na casa dos milhares de partidas simultâneas —
o limite prático é o número de conexões, não CPU nem memória.

Salas vivem na memória de **um** processo, então este servidor não escala
horizontalmente como está. Duas instâncias atrás de um balanceador colocariam
anfitrião e convidado em processos diferentes, e eles nunca se encontrariam. Se
um dia isso for necessário: sessões grudentas por código de sala, ou um Redis
pub/sub entre as instâncias.
