/// <reference path="../pb_data/types.d.ts" />

// A conversa direta entre dois amigos: texto, emoji e convite para partida,
// tudo no mesmo fio. Guardada aqui, e não no relay, para o amigo offline ler
// depois. Quem escreve e lê são só as rotas de `pb_hooks/conversa.pb.js`, que
// conferem a amizade e limpam o texto; nenhuma regra aberta.
//
// - `kind` "text": `text` limpo, de 1 a 120 caracteres;
// - `kind` "emote": `emote` é o índice em `ChatLog.EMOTES` do app;
// - `kind` "invite": `game` e `room`, a sala que o convite abriu.
//
// `read` marca o que `to` já viu. Apagar uma conta leva as mensagens dela.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  const messages = new Collection({
    type: "base",
    name: "direct_messages",
    listRule: null,
    viewRule: null,
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      { type: "relation", name: "from", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "relation", name: "to", required: true, collectionId: users.id, maxSelect: 1, cascadeDelete: true },
      { type: "select", name: "kind", required: true, values: ["text", "emote", "invite"], maxSelect: 1 },
      { type: "text", name: "text", max: 120 },
      { type: "number", name: "emote", onlyInt: true, min: 0 },
      { type: "text", name: "game", max: 20 },
      { type: "text", name: "room", max: 12 },
      { type: "bool", name: "read" },
      { type: "autodate", name: "created", onCreate: true },
    ],
    indexes: [
      "CREATE INDEX `idx_dm_pair` ON `direct_messages` (`from`, `to`, `created`)",
      "CREATE INDEX `idx_dm_unread` ON `direct_messages` (`to`, `read`)",
    ],
  })
  app.save(messages)
}, (app) => {
  app.delete(app.findCollectionByNameOrId("direct_messages"))
})
