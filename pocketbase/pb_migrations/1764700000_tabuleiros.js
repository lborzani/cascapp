/// <reference path="../pb_data/types.d.ts" />

// Os tabuleiros do xadrez e das damas voltam à loja (saíram na 1.66). Sem o
// registro em `shop_items` o item seria grátis, então entram com o preço de antes.
// Quem já tinha comprado continua com eles no `owned`.
const BOARDS = {
  board_wood: 200, board_marble: 300, board_tournament: 150,
  board_ocean: 200, board_neon: 300, board_candy: 250,
}

migrate((app) => {
  const shop = app.findCollectionByNameOrId("shop_items")
  for (const item of Object.keys(BOARDS)) {
    try {
      app.findFirstRecordByData("shop_items", "item", item)
      continue
    } catch (_) {
      // Ainda não está no catálogo.
    }
    const row = new Record(shop)
    row.set("item", item)
    row.set("price", BOARDS[item])
    row.set("exclusive", false)
    row.set("active", true)
    app.save(row)
  }
}, (app) => {
  for (const item of Object.keys(BOARDS)) {
    try {
      app.delete(app.findFirstRecordByData("shop_items", "item", item))
    } catch (_) {
      // Já não estava.
    }
  }
})
