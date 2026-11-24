/// <reference path="../pb_data/types.d.ts" />

// Os testadores: quem ajudou a construir o app desde o começo.
//
//   users.tester      ligado no painel admin (`/_/`); o hook (`pb_hooks/testador.pb.js`)
//                     manda o kit de agradecimento na hora
//   users.tester_kit  o kit já saiu: desligar e ligar de novo não manda outro
//
// Os dois são do servidor: a regra de atualização recusa o app escrevendo neles,
// e a criação (aberta) nasce com eles desligados. O presente do kit sai sem
// remetente (`gifts.from` vazio), e o app mostra "Do cascapp". Os itens do kit
// entram em `shop_items` como exclusivos: não se vendem, e a loja só os mostra a
// quem já tem.
const FIELDS = ["tester", "tester_kit"]
const KIT = ["frame_pioneer", "banner_pioneer", "title_pioneer", "name_pioneer", "ball_pioneer", "cue_pioneer", "finish_pioneer"]

migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  for (const name of FIELDS) {
    users.fields.add(new BoolField({ name: name }))
  }
  users.updateRule += FIELDS.map((name) => ` && @request.body.${name}:isset = false`).join("")
  app.save(users)

  const gifts = app.findCollectionByNameOrId("gifts")
  gifts.fields.getByName("from").required = false
  app.save(gifts)

  const shop = app.findCollectionByNameOrId("shop_items")
  for (const item of KIT) {
    try {
      app.findFirstRecordByData("shop_items", "item", item)
      continue
    } catch (_) {
      // Ainda não está no catálogo: entra como exclusivo.
    }
    const row = new Record(shop)
    row.set("item", item)
    row.set("price", 0)
    row.set("exclusive", true)
    row.set("active", true)
    app.save(row)
  }
}, (app) => {
  const users = app.findCollectionByNameOrId("users")
  for (const name of FIELDS) {
    users.fields.removeByName(name)
    users.updateRule = users.updateRule.replace(` && @request.body.${name}:isset = false`, "")
  }
  app.save(users)
  const gifts = app.findCollectionByNameOrId("gifts")
  gifts.fields.getByName("from").required = true
  app.save(gifts)
  for (const item of KIT) {
    try {
      app.delete(app.findFirstRecordByData("shop_items", "item", item))
    } catch (_) {}
  }
})
