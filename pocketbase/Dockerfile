# PocketBase das contas do Cascapp. Binário oficial fixado numa versão: subir de
# versão é trocar o ARG, ler as notas de release e rodar as migrations de novo.
#
# `TARGETARCH` vem do BuildKit com a arquitetura de quem constrói (amd64 no PC,
# arm64 na Raspberry), e os nomes batem com os do release do PocketBase. O
# builder antigo (`docker build` sem buildx, o da Pi) deixa ele vazio, e aí a
# arquitetura sai do `uname -m`.
FROM alpine:3.22

ARG PB_VERSION=0.40.5
ARG TARGETARCH

RUN ARCH="${TARGETARCH:-$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')}" \
    && apk add --no-cache ca-certificates unzip wget \
    && wget -q "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_${ARCH}.zip" -O /tmp/pb.zip \
    && unzip /tmp/pb.zip pocketbase -d /pb \
    && rm /tmp/pb.zip \
    && apk del unzip wget

COPY pb_migrations /pb/pb_migrations
COPY pb_hooks /pb/pb_hooks

EXPOSE 8090

# 0.0.0.0 dentro do container; quem limita ao localhost é o `ports` do compose.
CMD ["/pb/pocketbase", "serve", "--http=0.0.0.0:8090", "--dir=/pb/pb_data", "--migrationsDir=/pb/pb_migrations", "--hooksDir=/pb/pb_hooks"]
