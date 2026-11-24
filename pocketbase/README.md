# Contas (PocketBase)

PocketBase das contas do Cascapp, rodando no servidor de casa (`homeserver`, uma
Raspberry Pi 64 bits, Docker) atrás do Tailscale — a casa está em CGNAT. O relay
das partidas roda no mesmo compose e sai pelo túnel do Cloudflare
(`relay.cascapp.com.br`, ver `relay/README.md`). A imagem sai na arquitetura de quem constrói (`TARGETARCH` no
`Dockerfile`): arm64 no Pi, amd64 num PC.

| O quê | Onde | Quem alcança |
|---|---|---|
| O quê | Onde | Quem alcança |
|---|---|---|
| API | `https://api.cascapp.com.br/api/` | internet (túnel do Cloudflare, só `^/api/`) |
| Busca (`/search`) | `https://api.cascapp.com.br/search` | internet, só com token de conta (`worker/search.mjs`) |
| Painel admin | `https://homeserver.tailb8b7e1.ts.net:8092/_/` | só a tailnet (`tailscale serve`) |
| Container | `127.0.0.1:8092` no `homeserver` | só o próprio servidor |

O app usa `https://api.cascapp.com.br` como endereço base. O túnel do Cloudflare
(serviço `tunnel` do compose) tem duas rotas nesse hostname, configuradas no
painel (Zero Trust › Networks › Tunnels › `cascapp`): path `^/api/` para
`http://pocketbase:8090` e path `^/search$` para `http://search:8093`. Qualquer
outro caminho, como o painel `/_/`, cai no 404 do túnel. O túnel e não o Funnel
porque o ingresso do Funnel fica em Nova York: medido em 2026-11-21, ~280 ms por
pedido daqui, contra a borda do Cloudflare em São Paulo.

**Transição do Funnel:** as versões do app até a 1.56 usam
`https://homeserver.tailb8b7e1.ts.net:8443/cascapp` fixo. As três portas do
Funnel já têm dono (443 galaticos, 8443 ate-o-japao, 10000 SPMove), por isso o
Cascapp divide a 8443 pelos caminhos `/cascapp/api` e `/cascapp/search`. Eles
ficam no ar até essas versões sumirem. Nunca rodar `tailscale funnel` sem
`--https=`: isso troca a 443 do galaticos.

**Transição anterior:** antes ele morava no `mammus`, e as versões do app até a 1.41 têm
`https://mammus.tailb8b7e1.ts.net:8443` fixo. Enquanto elas existirem, a 8443
`/api` do `mammus` só repassa para o `homeserver`; depois a ponte é desligada.
A porta 443 do Funnel do `mammus` é do bot de música e não é tocada.

## Conta anônima

O app cria a própria conta no primeiro uso: e-mail sintético
`<hash>@anon.cascapp.invalid` e senha, os dois derivados por hash do id do
aparelho (`ANDROID_ID`) — reinstalar o app volta para a mesma conta. As
migrations em `pb_migrations/` deixam cada conta ver e mexer só em si mesma,
desligam alerta de login e OTP por e-mail (o e-mail não existe), limitam o nome
a 18 caracteres (o mesmo do app) e ligam o limite de requisições por IP — 30
contas novas e 60 entradas por minuto, folgado porque no celular uma operadora
inteira sai pelo mesmo IP (CGNAT). O IP real chega pelo `X-Forwarded-For` do
Funnel.

Backup automático todo dia às 4h, guardando 7, dentro do volume `pb_data`.

## Perfil público

Qualquer conta logada vê o perfil das outras: nome, avatar, código de amigo,
Elo do xadrez e o visual da loja (`look`, para a moldura, a capa, o título e a
cor do nome aparecerem para os amigos) — o e-mail não. Listar todas continua fechado; acha-se alguém
pelo código, em `GET /api/cascapp/by-code/{code}` (`pb_hooks/perfil.pb.js`).
O código e o Elo são do servidor: nascem no hook de criação e a regra de
atualização recusa qualquer pedido do app que tente escrevê-los.

## Elo do xadrez

Quem muda o Elo é o relay, depois de conferir que os dois jogadores contam o
mesmo desfecho: ele chama `POST /api/cascapp/chess-result`
(`pb_hooks/elo.pb.js`) com o segredo compartilhado no cabeçalho
`X-Cascapp-Relay`. A partida fica em `chess_games`, que cada um lê só as
próprias e nenhuma conta escreve. K 40 nas 20 primeiras partidas, 20 depois.

O segredo mora num `.env` no `homeserver`, ao lado do compose, e no Fly como secret
do relay — os dois iguais. Uma vez (o `read -s` evita que ele fique no
histórico do shell):

```bash
read -rs SECRET && printf 'CASCAPP_RELAY_SECRET=%s\n' "$SECRET" > ~/cascapp-contas/.env && chmod 600 ~/cascapp-contas/.env; unset SECRET
```

## Amigos

Adicionar pelo código de amigo (`POST /api/cascapp/friends/{code}`) vale para os
dois lados na hora: quem tem o código de alguém recebeu dele, então não há pedido
para aceitar. `GET /api/cascapp/friends` lista os amigos com o perfil público, e
`DELETE /api/cascapp/friends/{id}` desfaz dos dois lados. A coleção `friendships`
não tem regra aberta: só essas rotas (`pb_hooks/amigos.pb.js`) leem e escrevem.

Silenciar (`PUT /api/cascapp/friends/{id}/mute` com `{muted}`) marca só o lado
de quem silenciou (`friendships.muted`): as mensagens daquele amigo não viram
notificação, e o app não as conta na bolinha da pílula.

Bloquear (`POST /api/cascapp/blocks/{id}`) desfaz a amizade e os pedidos entre
os dois e grava em `blocks`. Enquanto durar, o pedido do bloqueado responde
"requested" como se tivesse ido, sem gravar nada (ele não fica sabendo), e o de
quem bloqueou recebe 409. `GET /api/cascapp/blocks` lista, e `DELETE
/api/cascapp/blocks/{id}` desbloqueia sem refazer a amizade. Teste:
`tests/blocks_probe.tscn`.

## Revisões de xadrez

Cada partida de xadrez que termina no app (online, contra o bot ou no mesmo
aparelho) vira um registro em `chess_reviews`, criado pelo próprio dono
(`Account.push_reviews`): os lances em UCI, o lado dele e quando foi jogada. O
worker de análise do servidor preenche depois; `status` vazio é pendente e só o
servidor o muda. Dono e `played_at` são únicos juntos, então o reenvio de uma
resposta perdida não duplica. Não passa pelo relay: a revisão é pessoal, e o
relay só conhece um hash da partida.

## Loja e moedas

Cada conta tem saldo (`coins`), itens pagos comprados (`owned`) e o visual
equipado (`look`, `{"ball": "ball_wood", "frame": "frame_neon", ...}`). O saldo
e os itens são do servidor: só as rotas de `pb_hooks/loja.pb.js` mexem neles,
e a regra de atualização recusa o app escrevendo `coins`, `owned` ou os campos
do dia. A conta nova nasce zerada por cima do que vier no corpo.

- `GET /api/cascapp/shop`, aberta: os preços (`items`), o bônus diário e o
  prêmio por partida. O catálogo mora na coleção `shop_items`, editada no
  painel admin (`/_/`): `price`, `active` (fora da loja quando falso; quem já
  tem segue usando) e `exclusive` (não se compra, só sai por missão). Item sem
  registro é grátis; item com registro só se equipa se estiver no `owned`. O
  app só desenha os ids que conhece (`core/cosmetics.gd`).
- `POST /api/cascapp/daily`: 50 moedas, uma vez por dia de Brasília.
- `POST /api/cascapp/reward` com `{game, result}`: 25 por vitória, 15 por
  empate e 10 por derrota, até 300 por dia. O app conta o próprio desfecho e o
  servidor confia, limitado pelo teto.
- `POST /api/cascapp/buy` com `{item}`: desconta numa transação; 402 sem saldo,
  409 já comprado, 404 item que não existe.
- O app equipa pelo update normal do `look`; um hook recusa (403) item pago que
  não está em `owned`.

As regras puras têm teste no Node (`node --test pocketbase/loja.test.js`), e as
rotas, no `tests/shop_probe.tscn` contra um PocketBase local.

### Missões e eventos

Editados no painel admin, sem deploy (`pb_migrations/1764100000_missoes.js`):

- `events`: `key`, `name`, `starts`, `ends`. Fora da janela, as missões do
  evento somem e não se resgatam.
- `missions`: `track` (`daily`: 3 sorteadas por conta e por dia; `perm`:
  conquista que nunca zera; `event`: precisa de `event`), `kind` (`play`, `win`,
  `variety` = jogos diferentes), `game` opcional, `target`, `title` opcional,
  `reward_coins`, `reward_item` (de `shop_items`, normalmente um exclusivo) e
  `active`. Um hook recusa missão que não paga nada, item que não está no
  catálogo e evento faltando ou sobrando.

Para criar um evento: um registro em `events`, as missões com `track = event`
apontando para ele e, se pagarem item novo, o item em `shop_items` com
`exclusive = true` (o desenho precisa já existir no app).

- `GET /api/cascapp/missions`: as missões valendo para quem pede, com
  `progress` e `claimed`, e os eventos no ar.
- `POST /api/cascapp/missions/claim` com `{key}`: paga moedas e item numa
  transação; 404 fora do ar, 409 incompleta ou já resgatada.
- O progresso anda no `/reward`, que devolve `missions_done`. O estado mora em
  `users.missions_state`, que o app não escreve.

Teste: `node --test pocketbase/missoes.test.js` e `tests/missions_probe.tscn`.

### Presentes

Só entre amigos (`pb_migrations/1764200000_presentes.js`, rotas em
`pb_hooks/presentes.pb.js`). Quem recebe ganha uma notificação, pelo mesmo
`push` da conversa.

- `POST /api/cascapp/gifts` com `{to, item}`: presente de um item à venda. Quem
  manda paga o preço do catálogo, e o item entra no `owned` do amigo na hora.
  404 sem amizade ou item fora de venda (exclusivo não se presenteia), 409 o
  amigo já tem, 402 sem saldo.
- `POST /api/cascapp/gifts/daily` com `{to}`: o presentinho de 10 moedas, de
  graça, um por amigo por dia; cada conta recebe no máximo 5 por dia (429). As
  moedas só entram quando o amigo abre.
- `GET /api/cascapp/gifts`: os presentes fechados que chegaram, `sent_today`
  (os amigos que já ganharam o meu presentinho hoje) e `daily_coins`.
- `POST /api/cascapp/gifts/{id}/open`: abre; 404 se não é meu ou já foi aberto.

Teste: `node --test pocketbase/presentes.test.js` e `tests/gifts_probe.tscn`.

## Conta protegida por e-mail

A credencial da conta anônima vem do `ANDROID_ID`, que muda quando o celular é
formatado. Quem quiser liga um e-mail à conta e, depois de formatar, volta para
ela com um código mandado para esse e-mail. Confirmado, o e-mail vai para o
`email` da conta (com `verified`) e para `contact_email`. O app continua
entrando com o e-mail sintético do aparelho, que mora em `device_login`
(oculto, segunda identidade de login em `passwordAuth.identityFields`). Só as
rotas de `pb_hooks/conta.pb.js` escrevem esses campos, e um e-mail protege uma
conta só.

- `POST /api/cascapp/email/start` com `{email, purpose}` (`protect` ou
  `recover`): manda um código de 6 dígitos, que vale 10 minutos e aceita 5
  tentativas. No máximo 3 envios por e-mail a cada 15 minutos e 10 por dia
  (429). Para recuperar, um e-mail sem conta responde 200 e nada sai.
- `POST /api/cascapp/email/protect` com `{code}`: grava o e-mail em `email` e
  `contact_email` na conta de quem pede, com `verified`, sem derrubar a sessão;
  409 se o e-mail já protege outra conta.
- `POST /api/cascapp/email/recover` com `{email, code, password}`, sendo
  `password` a do aparelho que pede: apaga a conta vazia de quem pede e grava o
  `device_login` e a senha dela na conta protegida. A próxima entrada normal
  do app cai na conta antiga. 403 senha errada, 400 código inválido (o motivo
  vai em `reason`) ou conta que já é deste aparelho.

O e-mail sai pelo SMTP das configurações do PocketBase (SES, `sa-east-1`), com
o remetente de `meta.senderAddress`. Com `CASCAPP_MAIL_CAPTURE=1` nada sai: o
código fica na memória e `GET /api/cascapp/test/last-code/{email}` o devolve.
Só os testes locais usam isso.

As regras puras têm teste no Node (`node --test pocketbase/conta.test.js`), e as
rotas, no `tests/recovery_probe.tscn` contra um PocketBase local com a captura.

## Subir ou atualizar

Do repositório, com acesso SSH ao `homeserver` pela tailnet (`USUARIO` é o seu
usuário no Pi):

```bash
tar -C pocketbase -cf - Dockerfile docker-compose.yml pb_migrations pb_hooks | ssh USUARIO@homeserver 'mkdir -p ~/cascapp-contas && tar -C ~/cascapp-contas -xf -'
ssh USUARIO@homeserver 'cd ~/cascapp-contas && docker build --network host -t cascapp-pocketbase:0.40.5 . && docker compose up -d --no-build'
```

O `--network host` é porque o BuildKit da Pi não resolve DNS (o host usa o
MagicDNS); o `--no-build` usa a imagem que acabou de sair.

As migrations rodam sozinhas na subida, e os hooks de `pb_hooks/` carregam junto. Versão nova do PocketBase: trocar o
`PB_VERSION` do `Dockerfile` e a tag da `image` no compose, ler as notas de
release e subir de novo.

Publicação pelo Tailscale (uma vez; fica salva no `tailscaled`):

```bash
tailscale funnel --bg --https=8443 --set-path=/cascapp/api http://127.0.0.1:8092/api
tailscale serve --bg --https=8092 http://127.0.0.1:8092
tailscale funnel --bg --https=8443 --set-path=/cascapp/search http://127.0.0.1:8093/search
```

## Superusuário

Uma vez, no `homeserver`. O `read -s` evita que a senha fique no histórico do shell:

```bash
read -rs PB_PASS && docker compose -f ~/cascapp-contas/docker-compose.yml exec pocketbase /pb/pocketbase superuser upsert SEU_EMAIL "$PB_PASS"; unset PB_PASS
```
