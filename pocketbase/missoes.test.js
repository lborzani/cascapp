// As regras puras das missões (`pb_hooks/missoes.js`), sem PocketBase:
//
//   node --test pocketbase/missoes.test.js
//
// Rotas, transação e o admin ficam no `tests/missions_probe.gd`.
const test = require("node:test")
const assert = require("node:assert")
const missoes = require("./pb_hooks/missoes.js")

const m = (key, track, kind, extra) =>
  Object.assign({ key, track, kind, game: "", target: 2, title: "", reward_coins: 10, reward_item: "", active: true, event: "" }, extra)

const POOL = ["a", "b", "c", "d", "e", "f", "g", "h"].map((k) => m("d_" + k, "daily", "play"))

test("sorteio diário: estável no dia, muda no outro, difere entre contas", () => {
  const keys = (user, day) => missoes.dailyPick(POOL, user, day).map((x) => x.key)
  assert.strictEqual(keys("u1", "2026-11-24").length, missoes.DAILY_COUNT)
  assert.deepStrictEqual(keys("u1", "2026-11-24"), keys("u1", "2026-11-24"))
  const days = new Set(["2026-11-24", "2026-11-25", "2026-11-26", "2026-11-27"].map((d) => keys("u1", d).join()))
  assert.ok(days.size > 1, "dias diferentes sorteiam diferente")
  const users = new Set(["u1", "u2", "u3", "u4"].map((u) => keys(u, "2026-11-24").join()))
  assert.ok(users.size > 1, "contas diferentes sorteiam diferente")
})

test("missões valendo: diárias, conquistas e evento só na janela", () => {
  const event = { id: "ev1", key: "natal", name: "Natal", starts: 1000, ends: 2000 }
  const all = POOL.concat([m("p_x", "perm", "win"), m("e_x", "event", "play", { event: "ev1" }), m("p_off", "perm", "play", { active: false })])
  const during = missoes.liveMissions(all, [event], "u1", "2026-11-24", 1500)
  assert.strictEqual(during.filter((x) => x.track === "daily").length, 3)
  assert.ok(during.every((x) => x.track !== "daily" || x.period === "d:2026-11-24"))
  assert.deepStrictEqual(during.filter((x) => x.track === "perm").map((x) => x.key), ["p_x"])
  const ev = during.find((x) => x.key === "e_x")
  assert.strictEqual(ev.period, "e:natal")
  assert.strictEqual(ev.eventKey, "natal")
  assert.ok(!missoes.liveMissions(all, [event], "u1", "2026-11-24", 999).some((x) => x.key === "e_x"), "antes da janela")
  assert.ok(!missoes.liveMissions(all, [event], "u1", "2026-11-24", 2000).some((x) => x.key === "e_x"), "no fim da janela")
})

test("progresso: jogar, vencer, jogo certo e jogos variados", () => {
  const live = [
    Object.assign(m("play", "perm", "play"), { period: "perm" }),
    Object.assign(m("win", "perm", "win"), { period: "perm" }),
    Object.assign(m("uno", "perm", "play", { game: "uno" }), { period: "perm" }),
    Object.assign(m("variety", "perm", "variety", { target: 3 }), { period: "perm" }),
  ]
  const state = {}
  assert.deepStrictEqual(missoes.advance(state, live, "chess", "loss"), [])
  const p = (key) => missoes.progressOf(state, live.find((x) => x.key === key))
  assert.deepStrictEqual([p("play"), p("win"), p("uno"), p("variety")], [1, 0, 0, 1])
  assert.deepStrictEqual(missoes.advance(state, live, "uno", "win"), ["play"])
  assert.deepStrictEqual([p("play"), p("win"), p("uno"), p("variety")], [2, 1, 1, 2])
  assert.deepStrictEqual(missoes.advance(state, live, "uno", "win"), ["win", "uno"])
  assert.strictEqual(p("variety"), 2, "o mesmo jogo não conta duas vezes")
  assert.deepStrictEqual(missoes.advance(state, live, "pool", "draw"), ["variety"])
  assert.deepStrictEqual(missoes.advance(state, live, "uno", "win"), [], "completa uma vez só")
  assert.strictEqual(p("play"), 2, "e não passa do alvo")
})

test("poda: tira dia passado e evento acabado, mantém conquistas", () => {
  const live = [{ period: "d:2026-11-25" }, { period: "e:natal" }]
  const state = { "d:2026-11-24": { p: {}, c: [], g: [] }, "d:2026-11-25": { p: { a: 1 }, c: [], g: [] }, "e:pascoa": {}, perm: { p: { x: 9 }, c: [], g: [] } }
  assert.deepStrictEqual(Object.keys(missoes.prune(state, live)).sort(), ["d:2026-11-25", "perm"])
})

test("missão salva pelo admin", () => {
  const shop = ["title_veteran"]
  assert.strictEqual(missoes.missionProblem(m("a", "daily", "play"), shop), "")
  assert.strictEqual(missoes.missionProblem(m("a", "perm", "play", { reward_coins: 0, reward_item: "title_veteran" }), shop), "")
  assert.notStrictEqual(missoes.missionProblem(m("a", "perm", "play", { reward_item: "title_nada" }), shop), "")
  assert.notStrictEqual(missoes.missionProblem(m("a", "event", "play"), shop), "", "evento sem evento")
  assert.notStrictEqual(missoes.missionProblem(m("a", "daily", "play", { event: "ev1" }), shop), "", "diária com evento")
  assert.notStrictEqual(missoes.missionProblem(m("a", "daily", "play", { reward_coins: 0 }), shop), "", "não paga nada")
})
