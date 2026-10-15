/// <reference path="../pb_data/types.d.ts" />

// Limites por IP maiores. No celular as operadoras usam CGNAT: muitos jogadores
// diferentes saem pelo mesmo IP público, e 10 entradas por minuto travariam uma
// operadora inteira na hora de pico. Os números novos ainda seguram um script
// criando contas em série, que é o abuso que o limite existe para barrar.
migrate((app) => {
  const settings = app.settings()
  settings.rateLimits.enabled = true
  settings.rateLimits.rules = [
    { label: "*:create", maxRequests: 30, duration: 60 },
    { label: "*:auth", maxRequests: 60, duration: 60 },
    { label: "/api/", maxRequests: 300, duration: 10 },
  ]
  app.save(settings)
}, (app) => {
  const settings = app.settings()
  settings.rateLimits.rules = [
    { label: "*:create", maxRequests: 5, duration: 60 },
    { label: "*:auth", maxRequests: 10, duration: 60 },
    { label: "/api/", maxRequests: 120, duration: 10 },
  ]
  app.save(settings)
})
