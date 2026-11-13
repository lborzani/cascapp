/// <reference path="../pb_data/types.d.ts" />

// O resultado da análise em `chess_reviews`, preenchido pelo worker
// (`pocketbase/worker`) com o superusuário dele. `analysis` é a análise crua de
// cada posição, da inicial à última analisada:
//
//   [{"wdl": [w, d, l], "mate": 0, "best": "e2e4", "pv": "e2e4 e7e5 …"}, …]
//
// do ponto de vista de quem tem a vez, no formato do `Stockfish.search` do app
// mais a PV. Os vereditos continuam no app (`GameReview`). `engine` diz com que
// motor e limite a análise saiu ("sf19 nodes=500000"), para o cache por posição
// saber o que pode reaproveitar.
//
// Quem cria o pedido é o dono, então ele não pode trazer o resultado pronto.
migrate((app) => {
  const reviews = app.findCollectionByNameOrId("chess_reviews")
  // Até 300 posições (o teto do worker) com PV de alguns lances cabem com folga.
  reviews.fields.add(new JSONField({ name: "analysis", maxSize: 400000 }))
  reviews.fields.add(new TextField({ name: "engine", max: 60 }))
  reviews.createRule = '@request.auth.id != "" && @request.body.owner = @request.auth.id && @request.body.status:isset = false && @request.body.analysis:isset = false && @request.body.engine:isset = false'
  app.save(reviews)
}, (app) => {
  const reviews = app.findCollectionByNameOrId("chess_reviews")
  reviews.fields.removeByName("analysis")
  reviews.fields.removeByName("engine")
  reviews.createRule = '@request.auth.id != "" && @request.body.owner = @request.auth.id && @request.body.status:isset = false'
  app.save(reviews)
})
