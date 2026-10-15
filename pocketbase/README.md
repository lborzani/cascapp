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
`<uuid>@anon.cascapp.invalid` e senha aleatória, guardados no aparelho. A
migration em `pb_migrations/` deixa cada conta ver e mexer só em si mesma,
desliga alerta de login e OTP por e-mail (o e-mail não existe), limita o nome a
18 caracteres (o mesmo do app) e liga o limite de requisições — 5 contas novas
por minuto por IP. O IP real chega pelo `X-Forwarded-For` do Funnel.

Backup automático todo dia às 4h, guardando 7, dentro do volume `pb_data`.

## Subir ou atualizar

Do repositório, com acesso SSH ao `mammus` pela tailnet:

```bash
tar -C pocketbase -cf - Dockerfile docker-compose.yml pb_migrations | ssh mammus@mammus 'mkdir -p ~/cascapp-contas && tar -C ~/cascapp-contas -xf -'
ssh mammus@mammus 'cd ~/cascapp-contas && docker compose up -d --build'
```

As migrations rodam sozinhas na subida. Versão nova do PocketBase: trocar o
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
