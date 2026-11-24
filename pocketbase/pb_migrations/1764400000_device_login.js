/// <reference path="../pb_data/types.d.ts" />

// O app entra com o e-mail sintético do aparelho (`Account._credentials`), e
// ele passa a morar em `device_login`, uma segunda identidade de login. Assim o
// `email` da conta fica livre para virar o e-mail real quando o jogador o
// confirma (rota `email/protect`, em `pb_hooks/conta.pb.js`), sem o app mudar
// a forma de entrar.
//
// `device_login` é oculto e só o servidor escreve: o hook de criação copia o
// `email` com que a conta nasce, e a recuperação o passa para a conta antiga.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users")
  users.fields.add(new TextField({ name: "device_login", hidden: true, max: 254 }))
  app.save(users)

  app.db().newQuery("UPDATE users SET device_login = email").execute()
  // As contas que já confirmaram um e-mail passam a tê-lo como o da conta.
  app.db().newQuery("UPDATE users SET email = contact_email, verified = TRUE WHERE contact_email != ''").execute()

  users.indexes.push("CREATE UNIQUE INDEX `idx_users_device_login` ON `users` (`device_login`) WHERE `device_login` != ''")
  users.passwordAuth.identityFields = ["email", "device_login"]
  users.createRule = "@request.body.device_login:isset = false"
  users.updateRule += " && @request.body.device_login:isset = false"
  app.save(users)
}, (app) => {
  const users = app.findCollectionByNameOrId("users")
  // Quem tinha o e-mail real volta a ter o sintético, senão o app não entra.
  app.db().newQuery("UPDATE users SET email = device_login WHERE device_login != ''").execute()
  users.passwordAuth.identityFields = ["email"]
  users.createRule = ""
  users.updateRule = users.updateRule.replace(" && @request.body.device_login:isset = false", "")
  users.indexes = users.indexes.filter((index) => !index.includes("idx_users_device_login"))
  users.fields.removeByName("device_login")
  app.save(users)
})
