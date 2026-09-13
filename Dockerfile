# Servidor de Bomberman do chess-checkers.
#
# É o único serviço em tempo real do app: os outros cinco jogos são por turno e
# falam pelo relay (`relay/`, outro app, Node/WebSocket). Este roda a simulação
# autoritativa de Bomberman a 30 Hz por sala, e é o mesmo projeto Godot do
# cliente, sem tela — `server/main.tscn` chama [BomberRoom], que chama
# [BomberRules], o mesmo arquivo que o celular roda.
#
# Duas etapas: a primeira busca o Godot, a segunda fica só com o que roda. Godot
# **padrão** e não o Mono: o projeto não tem C#, e a imagem com .NET carregaria um
# runtime inteiro pra rodar GDScript.

ARG GODOT_VERSION=4.7.1

FROM debian:bookworm-slim AS engine
ARG GODOT_VERSION
# Preenchido pelo BuildKit. Servidor de casa é ARM com frequência — deixar o arco
# ser detectado constrói em qualquer lugar em vez de falhar na execução com "exec
# format error", que não se parece nada com "baixei o binário errado".
ARG TARGETARCH
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*
RUN ARCH="${TARGETARCH:-$(dpkg --print-architecture)}" \
 && case "$ARCH" in \
      amd64) GODOT_ARCH="x86_64" ;; \
      arm64) GODOT_ARCH="arm64" ;; \
      armhf|arm) GODOT_ARCH="arm32" ;; \
      *) echo "não há build do Godot para $ARCH" >&2; exit 1 ;; \
    esac \
 && curl -sSLf -o /tmp/godot.zip \
      "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${GODOT_ARCH}.zip" \
 && unzip -q /tmp/godot.zip -d /tmp \
 && mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.${GODOT_ARCH}" /usr/local/bin/godot \
 && chmod +x /usr/local/bin/godot

FROM debian:bookworm-slim
# `libfontconfig1` porque o Godot carrega o servidor de texto mesmo sem tela — o
# projeto usa `SystemFont`, e sem fontconfig ele reclama na inicialização.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*
COPY --from=engine /usr/local/bin/godot /usr/local/bin/godot

WORKDIR /app
COPY . /app

# Importar na construção, e não na subida: a primeira execução de um projeto Godot
# varre e importa tudo, e pagar isso a cada partida de máquina é somar segundos de
# silêncio em que a porta já está aberta e ninguém atende.
RUN godot --headless --path /app --import 2>&1 | tail -5

# A imagem não sabe onde vai rodar, e é de propósito: quem sabe do ambiente é o
# `fly.toml`. Sem `BOMBER_BIND`, o servidor escuta no coringa, que é o certo atrás
# de um Docker comum.
EXPOSE 27016/udp

CMD ["godot", "--headless", "--path", "/app", "res://server/main.tscn"]
