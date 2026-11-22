/// <reference path="../pb_data/types.d.ts" />

// Pedidos de amizade. Até a 1.58, ler o código de alguém já fazia a amizade
// nos dois sentidos (`1760750000_amizades.js`). Só que o código não é segredo:
// quem assiste a uma sala pública chega ao id dos jogadores, e do id ao código.
// Agora ler o código manda um pedido (`from` quer ser amigo de `to`), e a
// amizade só nasce quando `to` aceita (`pb_hooks/amigos.pb.js`).
//
// As amizades que já existem continuam como estão. Como a `friendships`,
// nenhuma regra aberta: tudo passa pelas rotas, que só mexem nos pedidos de
// quem chama. Apagar uma conta leva os pedidos dela junto.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  const requests = new Collection({
    type: "base",
    name: "friend_requests",
    listRule: null,
    viewRule: null,
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      { type: "relation", name: "from", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "relation", name: "to", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "autodate", name: "created", onCreate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_friend_requests_pair` ON `friend_requests` (`from`, `to`)"],
  })
  app.save(requests)
}, (app) => {
  app.delete(app.findCollectionByNameOrId("friend_requests"))
})
