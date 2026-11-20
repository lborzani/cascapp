/// <reference path="../pb_data/types.d.ts" />

// A carteira da conta: moedas, itens comprados e o visual equipado.
//
// O saldo e os itens são do servidor. Só as rotas de `pb_hooks/loja.pb.js`
// mexem neles (bônus diário, prêmio por partida e compra), e a regra de
// atualização recusa qualquer pedido do app que tente escrevê-los. O `look`
// (o que está equipado) o app escreve pelo update normal; um hook confere que
// todo item pago nele está em `owned`.
//
//   coins          saldo
//   owned          ["ball_galaxy", ...] — só os itens pagos; os grátis não entram
//   look           {"ball": "ball_galaxy", "hair": "hair_mohawk", ...}
//   daily_day      "2026-11-16", o dia de Brasília do último bônus diário
//   earned_day     o dia de Brasília a que `earned_today` se refere
//   earned_today   moedas de partida já pagas nesse dia (o teto é do hook)
const FIELDS = ["coins", "owned", "look", "daily_day", "earned_day", "earned_today"]

migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  users.fields.add(new NumberField({ name: "coins", onlyInt: true, min: 0 }))
  users.fields.add(new JSONField({ name: "owned", maxSize: 4000 }))
  users.fields.add(new JSONField({ name: "look", maxSize: 1000 }))
  users.fields.add(new TextField({ name: "daily_day", max: 10 }))
  users.fields.add(new TextField({ name: "earned_day", max: 10 }))
  users.fields.add(new NumberField({ name: "earned_today", onlyInt: true, min: 0 }))
  users.updateRule += FIELDS
    .filter((name) => name !== "look")
    .map((name) => ` && @request.body.${name}:isset = false`)
    .join("")
  app.save(users)
}, (app) => {
  const users = app.findCollectionByNameOrId("users")
  for (const name of FIELDS) {
    users.fields.removeByName(name)
    users.updateRule = users.updateRule.replace(` && @request.body.${name}:isset = false`, "")
  }
  app.save(users)
})
