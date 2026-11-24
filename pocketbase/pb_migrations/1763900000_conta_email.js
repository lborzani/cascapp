/// <reference path="../pb_data/types.d.ts" />

// Conta protegida por e-mail (ver `pb_hooks/conta.pb.js`).
//
// O e-mail real mora em `contact_email`, e não no `email` da conta: o `email`
// continua sendo o sintético que o app deriva do aparelho, e é por ele que o
// app entra. Trocar um pelo outro faria uma simples reinstalação criar outra
// conta, porque o app não saberia mais qual e-mail mandar.
//
// `contact_email` só muda pelas rotas, depois de um código mandado para ele;
// a regra de atualização recusa o campo vindo do app. Um e-mail protege uma
// conta só (índice único, fora o vazio).
//
// `email_codes` guarda os códigos mandados, um registro por envio, só com o
// hash. Nenhuma regra aberta: só os hooks leem e escrevem. `user` é a conta
// que o código libera: a de quem pediu, para proteger; a conta antiga, para
// recuperar.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  users.fields.add(new EmailField({ name: "contact_email" }))
  users.indexes.push("CREATE UNIQUE INDEX `idx_users_contact_email` ON `users` (`contact_email`) WHERE `contact_email` != ''")
  users.updateRule += " && @request.body.contact_email:isset = false"
  app.save(users)

  const codes = new Collection({
    type: "base",
    name: "email_codes",
    listRule: null,
    viewRule: null,
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      { type: "text", name: "email", required: true, max: 254 },
      { type: "text", name: "purpose", required: true, max: 10 },
      { type: "text", name: "code_hash", required: true, max: 64 },
      { type: "relation", name: "user", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "number", name: "sent_at", onlyInt: true },
      { type: "number", name: "attempts", onlyInt: true, min: 0 },
    ],
    indexes: ["CREATE INDEX `idx_email_codes_email` ON `email_codes` (`email`, `sent_at`)"],
  })
  app.save(codes)
}, (app) => {
  app.delete(app.findCollectionByNameOrId("email_codes"))
  const users = app.findCollectionByNameOrId("users")
  users.fields.removeByName("contact_email")
  users.indexes = users.indexes.filter((index) => !index.includes("idx_users_contact_email"))
  users.updateRule = users.updateRule.replace(" && @request.body.contact_email:isset = false", "")
  app.save(users)
})
