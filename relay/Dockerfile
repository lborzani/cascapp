# Estágio de build: TypeScript e as dependências de desenvolvimento ficam aqui
# e não viajam para a imagem final.
FROM node:22-alpine AS build

WORKDIR /app

# Camada separada: as dependências mudam muito menos que o código, então editar
# o servidor não reinstala nada.
COPY package.json package-lock.json* ./
RUN npm install

COPY tsconfig.json ./
COPY src ./src
RUN npm run build


FROM node:22-alpine

WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080

COPY package.json package-lock.json* ./
RUN npm install --omit=dev && npm cache clean --force

COPY --from=build /app/dist ./dist

EXPOSE 8080
USER node
CMD ["node", "dist/main.js"]
