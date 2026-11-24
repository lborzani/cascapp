/// <reference path="../pb_data/types.d.ts" />

// Missões e eventos, editados no painel admin (`/_/`). Regras em
// `pb_hooks/missoes.js`, rotas em `pb_hooks/missoes.pb.js`.
//
// `events`: uma janela de tempo com nome. Fora dela, as missões do evento somem
// e não se resgatam.
//
// `missions`: uma missão de uma trilha:
//   track          daily (sorteada, 3 por dia), perm (conquista, nunca zera)
//                  ou event (vale só na janela de `event`)
//   kind           play (termine partidas), win (vença) ou variety (jogos diferentes)
//   game           opcional: só conta partidas deste jogo (vazio = qualquer um)
//   target         quantas
//   title          opcional: o texto da missão; vazio, o app escreve a partir do resto
//   reward_coins   moedas pagas no resgate
//   reward_item    item pago no resgate, de `shop_items` (normalmente um exclusivo)
//   active         fora do ar quando falso
//
// `users.missions_state`: o progresso, por período: `{"d:2026-11-24": {p: {key: n},
// c: [key], g: [jogo]}, "perm": {...}, "e:natal": {...}}`. `p` é o progresso,
// `c` o que já foi resgatado e `g` os jogos jogados no período (para `variety`).
// Só os hooks escrevem.
const GAMES = ["chess", "checkers", "battleship", "ludo", "monopoly", "uno", "pool", "bowling"]

const DAILY = [
  ["d_play3", "play", "", 3, 30],
  ["d_play5", "play", "", 5, 50],
  ["d_win2", "win", "", 2, 40],
  ["d_win4", "win", "", 4, 70],
  ["d_variety3", "variety", "", 3, 50],
  ["d_chess", "play", "chess", 2, 30],
  ["d_pool", "play", "pool", 2, 30],
  ["d_bowling", "play", "bowling", 2, 30],
  ["d_uno_win", "win", "uno", 1, 30],
  ["d_checkers_win", "win", "checkers", 1, 30],
]
// As conquistas que pagam um título exclusivo (o texto do título é do app,
// `core/cosmetics.gd`).
const PERM = [
  ["p_veteran", "play", "", 100, "title_veteran"],
  ["p_champion", "win", "", 50, "title_champion"],
  ["p_explorer", "variety", "", GAMES.length, "title_explorer"],
]

migrate((app) => {
  const events = new Collection({
    type: "base",
    name: "events",
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    fields: [
      { type: "text", name: "key", required: true, max: 40, pattern: "^[a-z0-9_]+$" },
      { type: "text", name: "name", required: true, max: 60 },
      { type: "date", name: "starts", required: true },
      { type: "date", name: "ends", required: true },
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_events_key` ON `events` (`key`)"],
  })
  app.save(events)

  const missions = new Collection({
    type: "base",
    name: "missions",
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    fields: [
      { type: "text", name: "key", required: true, max: 40, pattern: "^[a-z0-9_]+$" },
      { type: "select", name: "track", required: true, maxSelect: 1, values: ["daily", "perm", "event"] },
      { type: "relation", name: "event", collectionId: events.id, maxSelect: 1, cascadeDelete: true },
      { type: "select", name: "kind", required: true, maxSelect: 1, values: ["play", "win", "variety"] },
      { type: "select", name: "game", maxSelect: 1, values: GAMES },
      { type: "number", name: "target", required: true, onlyInt: true, min: 1 },
      { type: "text", name: "title", max: 80 },
      { type: "number", name: "reward_coins", onlyInt: true, min: 0 },
      { type: "text", name: "reward_item", max: 40 },
      { type: "bool", name: "active" },
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_missions_key` ON `missions` (`key`)"],
  })
  app.save(missions)

  const shop = app.findCollectionByNameOrId("shop_items")
  for (const [key, kind, game, target, item] of PERM) {
    const row = new Record(shop)
    row.set("item", item)
    row.set("price", 0)
    row.set("exclusive", true)
    row.set("active", true)
    app.save(row)
  }
  const add = (key, track, kind, game, target, coins, item) => {
    const row = new Record(missions)
    row.set("key", key)
    row.set("track", track)
    row.set("kind", kind)
    row.set("game", game)
    row.set("target", target)
    row.set("reward_coins", coins)
    row.set("reward_item", item)
    row.set("active", true)
    app.save(row)
  }
  for (const [key, kind, game, target, coins] of DAILY) {
    add(key, "daily", kind, game, target, coins, "")
  }
  for (const [key, kind, game, target, item] of PERM) {
    add(key, "perm", kind, game, target, 0, item)
  }

  const users = app.findCollectionByNameOrId("users")
  users.fields.add(new JSONField({ name: "missions_state", maxSize: 20000 }))
  users.updateRule += " && @request.body.missions_state:isset = false"
  app.save(users)
}, (app) => {
  app.delete(app.findCollectionByNameOrId("missions"))
  app.delete(app.findCollectionByNameOrId("events"))
  for (const [, , , , item] of PERM) {
    const row = app.findFirstRecordByData("shop_items", "item", item)
    app.delete(row)
  }
  const users = app.findCollectionByNameOrId("users")
  users.fields.removeByName("missions_state")
  users.updateRule = users.updateRule.replace(" && @request.body.missions_state:isset = false", "")
  app.save(users)
})
