#!/usr/bin/env bash
# Publica o relay (`relay/`) no servidor de casa e confere que ele responde.
#
#   tools/deploy_relay.sh
#
# Copia o código para `~/cascapp-relay` na Pi, constrói a imagem lá e recria o
# container `relay` do compose das contas (`pocketbase/docker-compose.yml`).
# Reiniciar o relay derruba as salas em curso: os apps reconectam sozinhos, mas
# rodar fora de horário de partida é mais gentil.
#
# `RELAY_HOST` troca o destino do SSH (padrão: a Pi pela tailnet, que funciona
# de dentro e de fora de casa).
set -euo pipefail

HOST="${RELAY_HOST:-mammus@100.79.138.96}"
SSH=(ssh -o HostKeyAlias=192.168.0.5 "$HOST")
cd "$(dirname "$0")/../relay"

tar -cf - Dockerfile package.json package-lock.json tsconfig.json src |
  "${SSH[@]}" 'mkdir -p ~/cascapp-relay && tar -C ~/cascapp-relay -xf -'

# `--network host`: o BuildKit da Pi não resolve DNS sozinho (ver o README das
# contas).
"${SSH[@]}" 'cd ~/cascapp-relay && docker build --network host -q -t cascapp-relay:latest . &&
  cd ~/cascapp-contas && docker compose up -d --no-build relay'

for _ in $(seq 1 20); do
  if curl -fsS https://relay.cascapp.com.br/healthz; then
    echo
    exit 0
  fi
  sleep 3
done
echo "o relay não respondeu em https://relay.cascapp.com.br/healthz" >&2
exit 1
