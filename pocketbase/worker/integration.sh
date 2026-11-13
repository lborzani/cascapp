#!/bin/sh
# Integração do worker num PocketBase descartável, sem tocar no de produção.
# Rodar de dentro de `pocketbase/` (na Pi: a cópia em ~/cascapp-teste):
#
#   sh worker/integration.sh
#
# Sobe uma rede, um PocketBase sem porta publicada e sem volume, um
# superusuário de teste, e roda o `integration.mjs` na imagem do worker.
# Tudo é apagado no fim, passe ou falhe.
set -eu

NET=cascapp-teste
PB=cascapp-pb-teste
PASS=$(head -c 18 /dev/urandom | base64 | tr -d '/+=')

cleanup() { docker rm -f "$PB" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker build -q --network host -t cascapp-pocketbase:teste . >/dev/null
docker build -q --network host -t cascapp-worker:teste worker >/dev/null

docker network create "$NET" >/dev/null
docker run -d --name "$PB" --network "$NET" cascapp-pocketbase:teste >/dev/null
sleep 3
docker exec "$PB" /pb/pocketbase superuser upsert worker@teste.invalid "$PASS" --dir=/pb/pb_data >/dev/null

docker run --rm --network "$NET" \
  -e PB_URL="http://$PB:8090" -e PB_EMAIL=worker@teste.invalid -e PB_PASSWORD="$PASS" \
  -e NODES="${NODES:-200000}" -e THREADS="${THREADS:-3}" \
  cascapp-worker:teste node /app/integration.mjs
