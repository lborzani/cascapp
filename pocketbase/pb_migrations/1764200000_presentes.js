/// <reference path="../pb_data/types.d.ts" />

// Presentes entre amigos (rotas em `pb_hooks/presentes.pb.js`). Dois tipos:
//
// - item da loja (`item`): quem manda paga o preço do catálogo e o item já entra
//   no `owned` de quem recebe na hora do envio, para ele não comprar o mesmo
//   enquanto não abre;
// - presentinho do dia (`coins`): de graça, um por amigo por dia; as moedas só
//   entram quando quem recebe abre.
//
// `day` é o dia de Brasília do envio, para os limites do presentinho. `opened`
// marca o que quem recebe já abriu. Nenhuma regra aberta: só as rotas leem e
// escrevem. Apagar uma conta leva os presentes dela.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  const gifts = new Collection({
    type: "base",
    name: "gifts",
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    fields: [
      { type: "relation", name: "from", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "relation", name: "to", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "text", name: "item", max: 40 },
      { type: "number", name: "coins", onlyInt: true, min: 0 },
      { type: "text", name: "day", required: true, max: 10 },
      { type: "bool", name: "opened" },
      { type: "autodate", name: "created", onCreate: true },
    ],
    indexes: [
      "CREATE INDEX `idx_gifts_inbox` ON `gifts` (`to`, `opened`)",
      "CREATE INDEX `idx_gifts_day` ON `gifts` (`day`, `to`, `from`)",
    ],
  })
  app.save(gifts)
}, (app) => {
  app.delete(app.findCollectionByNameOrId("gifts"))
})
