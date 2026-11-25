/// <reference path="../pb_data/types.d.ts" />

// O tabuleiro dos testadores (`board_pioneer`). Entra em `shop_items` como
// exclusivo (não se vende, e só se equipa com ele no `owned`) e no kit
// (`pb_hooks/presentes.js` `TESTER_KIT`), para quem virar testador daqui em
// diante. Quem já ganhou o kit recebe o tabuleiro num presente à parte, "Do
// cascapp", na caixa de Presentes.
const ITEM = "board_pioneer"
const MESSAGE = "Chegou peça nova no kit dos fundadores: o tabuleiro Pioneiro. Valeu por estar aqui desde o começo!"

migrate((app) => {
  try {
    app.findFirstRecordByData("shop_items", "item", ITEM)
  } catch (_) {
    const row = new Record(app.findCollectionByNameOrId("shop_items"))
    row.set("item", ITEM)
    row.set("price", 0)
    row.set("exclusive", true)
    row.set("active", true)
    app.save(row)
  }

  const gifts = app.findCollectionByNameOrId("gifts")
  // O dia de Brasília, como `loja.brDay`.
  const day = new Date(Date.now() - 3 * 3600 * 1000).toISOString().slice(0, 10)
  const testers = app.findRecordsByFilter("users", "tester_kit = true", "", 0, 0)
  for (let i = 0; i < testers.length; i++) {
    const user = testers[i]
    // O `owned` é um campo JSON: lido como texto, como `loja.jsonOf`.
    let owned = []
    try {
      owned = JSON.parse(user.getString("owned") || "[]") || []
    } catch (_) {
      owned = []
    }
    if (owned.includes(ITEM)) {
      continue
    }
    const gift = new Record(gifts)
    gift.set("to", user.id)
    gift.set("item", "")
    gift.set("coins", 0)
    gift.set("items", [ITEM])
    gift.set("message", MESSAGE)
    gift.set("day", day)
    gift.set("opened", false)
    app.save(gift)
  }
}, (app) => {
  try {
    app.delete(app.findFirstRecordByData("shop_items", "item", ITEM))
  } catch (_) {
    // Já não estava.
  }
})
