/// <reference path="../pb_data/types.d.ts" />

// Os testadores (ver `pb_migrations/1764600000_testador.js`). Ligar `tester` no
// painel admin manda o kit de agradecimento (`presentes.TESTER_KIT`) para a
// caixa de presentes da pessoa, uma vez só. Regras em `presentes.js`.

// A criação de conta é aberta: ninguém nasce testador pelo corpo do pedido.
onRecordCreate((e) => {
  e.record.set("tester", false)
  e.record.set("tester_kit", false)
  e.next()
}, "users")

// Depois de salvar: o kit sai só para quem é testador e ainda não ganhou. Ao
// marcar `tester_kit`, este hook roda de novo e para aí.
onRecordAfterUpdateSuccess((e) => {
  const presentes = require(`${__hooks}/presentes.js`)
  const loja = require(`${__hooks}/loja.js`)
  const user = e.record
  if (presentes.owesTesterKit(user.getBool("tester"), user.getBool("tester_kit"))) {
    e.app.runInTransaction((tx) => {
      const fresh = tx.findRecordById("users", user.id)
      if (!presentes.owesTesterKit(fresh.getBool("tester"), fresh.getBool("tester_kit"))) {
        return
      }
      const gift = new Record(tx.findCollectionByNameOrId("gifts"))
      gift.set("to", user.id)
      gift.set("item", "")
      gift.set("coins", 0)
      gift.set("items", presentes.TESTER_KIT)
      gift.set("message", presentes.TESTER_MESSAGE)
      gift.set("day", loja.brDay(Date.now()))
      gift.set("opened", false)
      tx.save(gift)
      fresh.set("tester_kit", true)
      tx.saveNoValidate(fresh)
    })
  }
  e.next()
}, "users")
