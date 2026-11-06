/// <reference path="../pb_data/types.d.ts" />

// Amizades. Uma linha por direção: `owner` tem `friend` na lista. Quem escreve
// aqui são só as rotas de `pb_hooks/amigos.pb.js`, que criam e apagam as duas
// direções juntas — ter o código de alguém é ter recebido dele, então adicionar
// já vale para os dois lados, sem pedido para aceitar.
//
// Nenhuma regra aberta: a lista sai pela rota, com o perfil público de cada
// amigo, e não pela coleção. Apagar uma conta leva as amizades dela junto.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  const friendships = new Collection({
    type: "base",
    name: "friendships",
    listRule: null,
    viewRule: null,
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      { type: "relation", name: "owner", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "relation", name: "friend", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "autodate", name: "created", onCreate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_friendships_pair` ON `friendships` (`owner`, `friend`)"],
  })
  app.save(friendships)
}, (app) => {
  app.delete(app.findCollectionByNameOrId("friendships"))
})
