/// <reference path="../pb_data/types.d.ts" />

// O kit: um presente com vários itens e um bilhete, criado à mão no painel
// admin (`/_/`), como o agradecimento aos testadores. Os presentes entre
// amigos (`1764200000_presentes.js`) não usam estes campos.
//
//   items    ["frame_pioneer", ...] — entram no `owned` de quem recebe quando
//            ele abre (o kit não passa pela rota de envio, que entrega na hora)
//   message  o bilhete que aparece com o presente aberto
//
// Os ids precisam estar em `shop_items`; o hook recusa o resto ao salvar.
migrate((app) => {
  const gifts = app.findCollectionByNameOrId("gifts")
  gifts.fields.add(new JSONField({ name: "items", maxSize: 2000 }))
  gifts.fields.add(new TextField({ name: "message", max: 200 }))
  app.save(gifts)
}, (app) => {
  const gifts = app.findCollectionByNameOrId("gifts")
  gifts.fields.removeByName("items")
  gifts.fields.removeByName("message")
  app.save(gifts)
})
