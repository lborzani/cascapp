# Worker de análise do mentor de xadrez: Node + Stockfish 19 compilado. O APK
# leva o 15.1 sem rede (mais leve); aqui fica o 19, mais fundo, porque a
# análise do servidor é a que vale com internet.
#
# `SF_ARCH` padrão é o da Raspberry Pi 5 (Cortex-A76, com dotprod). Num PC:
# `--build-arg SF_ARCH=x86-64-avx2`. O `make` baixa as redes NNUE, então na Pi o
# build precisa de `--network host` (o BuildKit de lá não resolve DNS).
FROM node:24-bookworm-slim AS stockfish

ARG SF_TAG=sf_19
ARG SF_ARCH=armv8-dotprod

RUN apt-get update \
    && apt-get install -y --no-install-recommends g++ make curl ca-certificates \
    && curl -fsSL "https://github.com/official-stockfish/Stockfish/archive/refs/tags/${SF_TAG}.tar.gz" | tar -xz -C /tmp \
    && make -C "/tmp/Stockfish-${SF_TAG}/src" -j"$(nproc)" build ARCH="${SF_ARCH}" \
    && strip "/tmp/Stockfish-${SF_TAG}/src/stockfish" \
    && cp "/tmp/Stockfish-${SF_TAG}/src/stockfish" /stockfish

FROM node:24-bookworm-slim

COPY --from=stockfish /stockfish /usr/local/bin/stockfish
COPY worker.mjs search.mjs integration.mjs /app/

ENV STOCKFISH=/usr/local/bin/stockfish
USER node
CMD ["node", "/app/worker.mjs"]
