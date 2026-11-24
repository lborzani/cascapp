/// <reference path="../pb_data/types.d.ts" />

// O catálogo da loja vira dado, editado no painel admin (`/_/`), e não mais a
// constante `PRICES` do `pb_hooks/loja.js`. Um registro por item pago:
//
//   item       o id do item, o mesmo de `core/cosmetics.gd` no app
//   price      o preço em moedas
//   exclusive  não se compra: só sai por missão (e mais tarde por evento)
//   active     fora da loja quando falso; quem já tem continua usando
//
// Item que não tem registro aqui é grátis (as cores, por exemplo). Item com
// registro, em qualquer estado, só se equipa se estiver no `owned` da conta.
// Nenhuma regra aberta: só os hooks e o superusuário leem e escrevem.
//
// O app só desenha itens que conhece. Um id novo aqui sem o desenho no app não
// aparece na loja dessa versão.
const SEED = {
  ball_galaxy: 400, ball_flames: 300, ball_ocean: 250, ball_melon: 200, ball_wood: 150,
  ball_checker: 200, ball_chrome: 400, ball_neon: 450, ball_crystal: 500, ball_lava: 450,
  frame_gold: 300, frame_silver: 200, frame_neon: 250, frame_flames: 350, frame_laurel: 400, frame_rainbow: 450,
  banner_sunset: 200, banner_night: 250, banner_felt: 150, banner_checker: 150, banner_waves: 200, banner_aurora: 400,
  title_pool: 150, title_chess: 150, title_strike: 150, title_board: 150, title_uno: 100,
  title_boteco: 250, title_lucky: 100, title_unbeaten: 250,
  name_gold: 200, name_ruby: 150, name_emerald: 150, name_neon: 200, name_rainbow: 300,
  finish_wood: 200, finish_marble: 250, finish_metal: 350, finish_neon: 300, finish_gems: 350,
  pieces_staunton: 400, pieces_minimal: 400, pieces_medieval: 400,
  cue_ebony: 250, cue_carbon: 300, cue_flames: 200, cue_neon: 350, cue_gold: 400,
}

migrate((app) => {
  const items = new Collection({
    type: "base",
    name: "shop_items",
    listRule: null,
    viewRule: null,
    createRule: null,
    updateRule: null,
    deleteRule: null,
    fields: [
      { type: "text", name: "item", required: true, max: 40, pattern: "^[a-z0-9_]+$" },
      { type: "number", name: "price", onlyInt: true, min: 0 },
      { type: "bool", name: "exclusive" },
      { type: "bool", name: "active" },
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_shop_items_item` ON `shop_items` (`item`)"],
  })
  app.save(items)
  for (const item of Object.keys(SEED)) {
    const record = new Record(items)
    record.set("item", item)
    record.set("price", SEED[item])
    record.set("exclusive", false)
    record.set("active", true)
    app.save(record)
  }
}, (app) => {
  app.delete(app.findCollectionByNameOrId("shop_items"))
})
