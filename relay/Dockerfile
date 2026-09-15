# Estágio de build: TypeScript e as dependências de desenvolvimento ficam aqui
# e não viajam para a imagem final.
FROM node:22-alpine AS build

WORKDIR /app

# Camada separada: as dependências mudam muito menos que o código, então editar
# o servidor não reinstala nada.
# `npm ci` e não `npm install`, pelo mesmo motivo que a esteira de CI usa: ele
# obedece ao lockfile em vez de resolver versões de novo. Com `install`, a imagem
# que roda em produção podia ser construída contra uma versão que ninguém testou
# — e era a única etapa do projeto que ainda fazia isso.
COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src
RUN npm run build


FROM node:22-alpine

WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY --from=build /app/dist ./dist

EXPOSE 8080
USER node
CMD ["node", "dist/main.js"]
