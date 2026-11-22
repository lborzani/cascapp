/// <reference path="../pb_data/types.d.ts" />

// O token do Firebase de cada aparelho, para a notificação de mensagem de
// amigo com o app fechado (`pb_hooks/conversa.pb.js` → serviço `push`). Uma
// conta pode ter vários aparelhos; um token é de um aparelho só, e o índice
// único garante isso: o mesmo celular entrando em outra conta leva o token
// junto (`PUT /api/cascapp/push-token`).
//
// Nenhuma regra aberta: o app escreve pela rota, e só o hook lê. Apagar uma
// conta leva os tokens dela.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  const tokens = new Collection({
    type: "base",
    name: "push_tokens",
    listRule: null,
    viewRule: null,
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      { type: "relation", name: "owner", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "text", name: "token", required: true, max: 500 },
      { type: "autodate", name: "updated", onCreate: true, onUpdate: true },
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_push_tokens_token` ON `push_tokens` (`token`)",
      "CREATE INDEX `idx_push_tokens_owner` ON `push_tokens` (`owner`)",
    ],
  })
  app.save(tokens)
}, (app) => {
  app.delete(app.findCollectionByNameOrId("push_tokens"))
})
