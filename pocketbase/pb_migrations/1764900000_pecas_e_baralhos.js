/// <reference path="../pb_data/types.d.ts" />

// As peças do Metrópole (`token_*`) e os baralhos do Uno (`deck_*`) entram na
// loja com preço. Os dois dos testadores (`token_pioneer`, `deck_pioneer`) entram
// como exclusivos e no kit (`pb_hooks/presentes.js` `TESTER_KIT`); quem já ganhou
// o kit recebe os dois num presente à parte, "Do cascapp", na caixa de Presentes.
const PRICES = {
  token_crown: 400, token_rocket: 300, token_cat: 250, token_dino: 350, token_guitar: 300, token_die: 200,
  deck_retro: 200, deck_gold: 350, deck_neon: 300, deck_night: 250, deck_candy: 250,
}
const PIONEER = ["token_pioneer", "deck_pioneer"]
const MESSAGE = "Mais peças no kit dos fundadores: a Estrela Pioneira no Metrópole e o baralho Pioneiro no Uno. Valeu por estar aqui desde o começo!"

migrate((app) => {
  const shop = app.findCollectionByNameOrId("shop_items")
  const add = (item, price, exclusive) => {
    try {
      app.findFirstRecordByData("shop_items", "item", item)
      return
    } catch (_) {
      // Ainda não está no catálogo.
    }
    const row = new Record(shop)
    row.set("item", item)
    row.set("price", price)
    row.set("exclusive", exclusive)
    row.set("active", true)
    app.save(row)
  }
  for (const item of Object.keys(PRICES)) add(item, PRICES[item], false)
  for (const item of PIONEER) add(item, 0, true)

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
    const missing = PIONEER.filter((item) => !owned.includes(item))
    if (missing.length === 0) continue
    const gift = new Record(gifts)
    gift.set("to", user.id)
    gift.set("item", "")
    gift.set("coins", 0)
    gift.set("items", missing)
    gift.set("message", MESSAGE)
    gift.set("day", day)
    gift.set("opened", false)
    app.save(gift)
  }
}, (app) => {
  for (const item of Object.keys(PRICES).concat(PIONEER)) {
    try {
      app.delete(app.findFirstRecordByData("shop_items", "item", item))
    } catch (_) {
      // Já não estava.
    }
  }
})
