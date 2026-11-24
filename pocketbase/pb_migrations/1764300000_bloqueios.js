/// <reference path="../pb_data/types.d.ts" />

// Bloquear e silenciar amigos (rotas em `pb_hooks/amigos.pb.js`).
//
// - `blocks`: `owner` bloqueou `blocked`. Bloquear desfaz a amizade e os
//   pedidos entre os dois; enquanto a linha existir, o pedido de `blocked` para
//   `owner` finge que foi e não grava nada, e o de `owner` para `blocked` é
//   recusado (409) até desbloquear. Nenhuma regra aberta.
// - `friendships.muted`: o dono não quer aviso das mensagens desse amigo. Só o
//   lado de quem silenciou; desfazer a amizade leva junto.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  const blocks = new Collection({
    type: "base",
    name: "blocks",
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    fields: [
      { type: "relation", name: "owner", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "relation", name: "blocked", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "autodate", name: "created", onCreate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_blocks_pair` ON `blocks` (`owner`, `blocked`)"],
  })
  app.save(blocks)

  const friendships = app.findCollectionByNameOrId("friendships")
  friendships.fields.add(new BoolField({ name: "muted" }))
  app.save(friendships)
}, (app) => {
  const friendships = app.findCollectionByNameOrId("friendships")
  friendships.fields.removeByName("muted")
  app.save(friendships)
  app.delete(app.findCollectionByNameOrId("blocks"))
})
