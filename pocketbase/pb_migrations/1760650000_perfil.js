/// <reference path="../pb_data/types.d.ts" />

// Perfil público da conta: avatar, código de amigo e Elo do xadrez.
//
// Até aqui cada conta só via a si mesma. Agora qualquer conta logada vê o perfil
// das outras — nome, avatar, código e Elo; o e-mail sintético continua
// escondido (`emailVisibility` falso). Listar todas segue fechado: acha-se
// alguém pelo código de amigo (`pb_hooks/perfil.pb.js`).
//
// O código e o Elo são do servidor. `pb_hooks/perfil.pb.js` sorteia o código e
// zera o Elo em 1200 na criação, por cima do que vier no corpo, e a regra de
// atualização recusa qualquer pedido que tente escrevê-los: quem mexe no Elo é
// o relay, pela rota do resultado, nunca o app.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users")

  // O `avatar` já nasce com a coleção, aceitando até 5 MB e SVG. O app recorta,
  // reduz a 256×256 e comprime antes de subir; o teto aqui é folgado para isso
  // e apertado para quem pular o app. SVG fora: é documento, não foto.
  const avatar = users.fields.getByName("avatar")
  avatar.maxSize = 100 * 1024
  avatar.mimeTypes = ["image/webp", "image/jpeg", "image/png"]
  avatar.thumbs = ["128x128"]
  users.fields.add(new TextField({ name: "friend_code", max: 6 }))
  users.fields.add(new NumberField({ name: "elo_chess", onlyInt: true }))
  users.fields.add(new NumberField({ name: "games_chess", onlyInt: true, min: 0 }))

  users.indexes.push(
    "CREATE UNIQUE INDEX `idx_users_friend_code` ON `users` (`friend_code`) WHERE `friend_code` != ''"
  )

  users.viewRule = "@request.auth.id != ''"
  users.updateRule = "id = @request.auth.id" +
    " && @request.body.friend_code:isset = false" +
    " && @request.body.elo_chess:isset = false" +
    " && @request.body.games_chess:isset = false"

  app.save(users)

  // As contas que já existem ganham código e Elo inicial agora. Mesmo alfabeto
  // do hook: sem 0/O nem 1/I/L, que se confundem lidos em voz alta.
  for (const record of app.findAllRecords("users")) {
    let code
    do {
      code = $security.randomStringWithAlphabet(6, "ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    } while (app.countRecords("users", $dbx.hashExp({ friend_code: code })) > 0)
    record.set("friend_code", code)
    record.set("elo_chess", 1200)
    record.set("games_chess", 0)
    app.saveNoValidate(record)
  }
}, (app) => {
  const users = app.findCollectionByNameOrId("users")
  for (const name of ["friend_code", "elo_chess", "games_chess"]) {
    users.fields.removeByName(name)
  }
  users.indexes = users.indexes.filter((index) => !index.includes("idx_users_friend_code"))
  users.viewRule = "id = @request.auth.id"
  users.updateRule = "id = @request.auth.id"
  app.save(users)
})
