/// <reference path="../pb_data/types.d.ts" />

// Contas do Cascapp. A coleção `users` já nasce com o PocketBase; aqui ela é
// ajustada para conta anônima: o app cria a própria conta com um e-mail
// sintético e uma senha aleatória, e ninguém confirma e-mail nenhum.
migrate((app) => {
  const users = app.findCollectionByNameOrId("users")

  // Mesmo limite do campo de nome no app (Prefs.NAME_LIMIT).
  const name = users.fields.getByName("name")
  name.max = 18

  // Ninguém lista os outros, cada um só vê e mexe na própria conta. Criar é
  // livre: é a conta anônima nascendo no primeiro uso do app.
  users.listRule = "id = @request.auth.id"
  users.viewRule = "id = @request.auth.id"
  users.createRule = ""
  users.updateRule = "id = @request.auth.id"
  users.deleteRule = "id = @request.auth.id"

  // O e-mail é sintético (`...@anon.cascapp.invalid`): alerta de login novo,
  // OTP e redefinição de senha por e-mail não chegariam a lugar nenhum.
  users.authAlert.enabled = false
  users.otp.enabled = false

  app.save(users)

  const settings = app.settings()
  settings.meta.appName = "Cascapp"
  // Backup diário às 4h, guardando uma semana, dentro do pb_data (volume).
  settings.backups.cron = "0 4 * * *"
  settings.backups.cronMaxKeep = 7
  // Conta anônima é criada sem login, então é o endpoint mais fácil de abusar.
  settings.rateLimits.enabled = true
  settings.rateLimits.rules = [
    { label: "*:create", maxRequests: 5, duration: 60 },
    { label: "*:auth", maxRequests: 10, duration: 60 },
    { label: "/api/", maxRequests: 120, duration: 10 },
  ]
  // Tudo chega pelo proxy do Tailscale Funnel, que repassa o IP do jogador no
  // X-Forwarded-For. Sem isto o limite acima valeria para todos juntos.
  settings.trustedProxy.headers = ["X-Forwarded-For"]
  settings.trustedProxy.useLeftmostIP = false
  app.save(settings)
}, (app) => {
  const users = app.findCollectionByNameOrId("users")
  users.authAlert.enabled = true
  app.save(users)
})
