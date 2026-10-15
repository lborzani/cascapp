# PocketBase das contas do Cascapp. Binário oficial fixado numa versão: subir de
# versão é trocar o ARG, ler as notas de release e rodar as migrations de novo.
FROM alpine:3.22

ARG PB_VERSION=0.40.5

RUN apk add --no-cache ca-certificates unzip wget \
    && wget -q "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip" -O /tmp/pb.zip \
    && unzip /tmp/pb.zip pocketbase -d /pb \
    && rm /tmp/pb.zip \
    && apk del unzip wget

COPY pb_migrations /pb/pb_migrations

EXPOSE 8090

# 0.0.0.0 dentro do container; quem limita ao localhost é o `ports` do compose.
CMD ["/pb/pocketbase", "serve", "--http=0.0.0.0:8090", "--dir=/pb/pb_data", "--migrationsDir=/pb/pb_migrations"]
