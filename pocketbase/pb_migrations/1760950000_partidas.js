/// <reference path="../pb_data/types.d.ts" />

// Partidas de todos os jogos, para o perfil que os amigos veem
// (`GET /api/cascapp/friends/{id}/profile` em `pb_hooks/amigos.pb.js`).
//
// Cada aparelho sobe as próprias, contra o bot e online (no mesmo aparelho não
// há "eu" contra alguém). O servidor confia no que o app diz: é estatística de
// amigos, e não ranking. O Elo do xadrez continua arbitrado pelo relay em
// `chess_games`.
//
// A mesma partida mandada de novo (resposta perdida) bate no índice único e
// é recusada com 400, que o app trata como "já está lá". A conta lê as
// próprias; o amigo lê pela rota, que confere a amizade.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  const matches = new Collection({
    type: "base",
    name: "matches",
    listRule: "owner = @request.auth.id",
    viewRule: "owner = @request.auth.id",
    createRule: "@request.auth.id != '' && owner = @request.auth.id",
    updateRule: null,
    deleteRule: null,
    fields: [
      { type: "relation", name: "owner", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "text", name: "game", required: true, max: 20, pattern: "^[a-z_]+$" },
      { type: "select", name: "mode", required: true, values: ["solo", "online"], maxSelect: 1 },
      { type: "select", name: "result", required: true, values: ["win", "loss", "draw"], maxSelect: 1 },
      { type: "text", name: "against", max: 80 },
      { type: "text", name: "detail", max: 120 },
      { type: "number", name: "played_at", required: true, onlyInt: true, min: 1 },
      { type: "autodate", name: "created", onCreate: true },
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_matches_once` ON `matches` (`owner`, `game`, `played_at`)",
      "CREATE INDEX `idx_matches_recent` ON `matches` (`owner`, `played_at`)",
    ],
  })
  app.save(matches)
}, (app) => {
  app.delete(app.findCollectionByNameOrId("matches"))
})
