/// <reference path="../pb_data/types.d.ts" />

// Pedidos de revisão de xadrez: o app sobe cada partida que terminou (online,
// contra o bot ou no mesmo aparelho) com os lances em UCI, e o worker de análise
// no servidor de casa preenche. Ver o mentor de xadrez no README.
//
// Quem cria é o próprio dono, e não o relay: a revisão é pessoal — quem mentir
// os lances só engana a si mesmo — e o relay só conhece um hash da partida.
// `status` vazio é pendente; só o servidor o muda, por isso o pedido não pode
// trazê-lo, e ninguém atualiza ou apaga pela API.
//
// `played_at` (unix, do aparelho) com o dono é a chave: o app que reenvia
// depois de perder a resposta não duplica. Apagar a conta leva as revisões.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  const reviews = new Collection({
    type: "base",
    name: "chess_reviews",
    listRule: "owner = @request.auth.id",
    viewRule: "owner = @request.auth.id",
    createRule: '@request.auth.id != "" && @request.body.owner = @request.auth.id && @request.body.status:isset = false',
    updateRule: null,
    deleteRule: null,
    fields: [
      { type: "relation", name: "owner", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      // Até 2000 meios-lances (o teto do relay) de "e7e8q " cada.
      {
        type: "text", name: "moves", required: true, max: 12000,
        pattern: "^[a-h][1-8][a-h][1-8][qrbn]?( [a-h][1-8][a-h][1-8][qrbn]?)*$",
      },
      // O lado do dono. No mesmo aparelho (`hotseat`) os dois lados são dele.
      { type: "select", name: "side", required: true, values: ["white", "black"], maxSelect: 1 },
      { type: "bool", name: "hotseat" },
      { type: "text", name: "against", max: 60 },
      { type: "number", name: "played_at", required: true, onlyInt: true, min: 1 },
      { type: "select", name: "status", values: ["done", "failed"], maxSelect: 1 },
      { type: "autodate", name: "created", onCreate: true },
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_chess_reviews_game` ON `chess_reviews` (`owner`, `played_at`)",
      "CREATE INDEX `idx_chess_reviews_status` ON `chess_reviews` (`status`)",
    ],
  })
  app.save(reviews)
}, (app) => {
  app.delete(app.findCollectionByNameOrId("chess_reviews"))
})
