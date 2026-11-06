/// <reference path="../pb_data/types.d.ts" />

// Partidas de xadrez que contaram para o Elo. Quem escreve aqui é só a rota do
// resultado (`pb_hooks/elo.pb.js`), chamada pelo relay; nenhuma conta cria,
// muda ou apaga. Cada jogador lê as próprias.
//
// `key` identifica a partida (a sala e a sequência dos lances, montada pelo
// relay) e é única: o mesmo resultado mandado duas vezes — reconexão, relay
// repetindo — conta uma vez só.
//
// Apagar uma conta leva as partidas dela junto (`cascadeDelete`); sem isso o
// painel não apagaria conta nenhuma que já jogou. O Elo do outro fica como está.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  const games = new Collection({
    type: "base",
    name: "chess_games",
    listRule: "white = @request.auth.id || black = @request.auth.id",
    viewRule: "white = @request.auth.id || black = @request.auth.id",
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      { type: "text", name: "key", required: true, max: 200 },
      { type: "relation", name: "white", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "relation", name: "black", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "select", name: "result", required: true, values: ["white", "black", "draw"], maxSelect: 1 },
      { type: "number", name: "plies", onlyInt: true, min: 0 },
      { type: "number", name: "white_elo", onlyInt: true },
      { type: "number", name: "white_delta", onlyInt: true },
      { type: "number", name: "black_elo", onlyInt: true },
      { type: "number", name: "black_delta", onlyInt: true },
      { type: "autodate", name: "created", onCreate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_chess_games_key` ON `chess_games` (`key`)"],
  })
  app.save(games)
}, (app) => {
  app.delete(app.findCollectionByNameOrId("chess_games"))
})
