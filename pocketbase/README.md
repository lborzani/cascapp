# Contas (PocketBase)

PocketBase das contas do Cascapp, rodando no servidor de casa (`mammus`, Ubuntu,
Docker) atrás do Tailscale — a casa está em CGNAT e não há domínio próprio.

| O quê | Onde | Quem alcança |
|---|---|---|
| API | `https://mammus.tailb8b7e1.ts.net:8443/api/` | internet (Tailscale Funnel, só `/api`) |
| Painel admin | `https://mammus.tailb8b7e1.ts.net:8091/_/` | só a tailnet (`tailscale serve`) |
| Container | `127.0.0.1:8090` no `mammus` | só o próprio servidor |

A porta 443 do Funnel é do bot de música (`/` → `:3000`) e não é tocada.

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

Qualquer conta logada vê o perfil das outras: nome, avatar, código de amigo e
Elo do xadrez — o e-mail não. Listar todas continua fechado; acha-se alguém
pelo código, em `GET /api/cascapp/by-code/{code}` (`pb_hooks/perfil.pb.js`).
O código e o Elo são do servidor: nascem no hook de criação e a regra de
atualização recusa qualquer pedido do app que tente escrevê-los.

## Elo do xadrez

Quem muda o Elo é o relay, depois de conferir que os dois jogadores contam o
mesmo desfecho: ele chama `POST /api/cascapp/chess-result`
(`pb_hooks/elo.pb.js`) com o segredo compartilhado no cabeçalho
`X-Cascapp-Relay`. A partida fica em `chess_games`, que cada um lê só as
próprias e nenhuma conta escreve. K 40 nas 20 primeiras partidas, 20 depois.

O segredo mora num `.env` no `mammus`, ao lado do compose, e no Fly como secret
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

## Subir ou atualizar

Do repositório, com acesso SSH ao `mammus` pela tailnet:

```bash
tar -C pocketbase -cf - Dockerfile docker-compose.yml pb_migrations pb_hooks | ssh mammus@mammus 'mkdir -p ~/cascapp-contas && tar -C ~/cascapp-contas -xf -'
ssh mammus@mammus 'cd ~/cascapp-contas && docker compose up -d --build'
```

As migrations rodam sozinhas na subida, e os hooks de `pb_hooks/` carregam junto. Versão nova do PocketBase: trocar o
`PB_VERSION` do `Dockerfile` e a tag da `image` no compose, ler as notas de
release e subir de novo.

Publicação pelo Tailscale (uma vez; fica salva no `tailscaled`):

```bash
tailscale funnel --bg --https=8443 --set-path=/api http://127.0.0.1:8090/api
tailscale serve --bg --https=8091 http://127.0.0.1:8090
```

## Superusuário

Uma vez, no `mammus`. O `read -s` evita que a senha fique no histórico do shell:

```bash
read -rs PB_PASS && docker compose -f ~/cascapp-contas/docker-compose.yml exec pocketbase /pb/pocketbase superuser upsert SEU_EMAIL "$PB_PASS"; unset PB_PASS
```
