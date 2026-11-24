// Comum às rotas das missões (ver `pb_migrations/1764100000_missoes.js`). Sem
// `.pb.js` no nome: só entra por `require`. As funções puras recebem as missões,
// os eventos e o estado já lidos, e `pocketbase/missoes.test.js` as testa no Node.

const DAILY_COUNT = 3

// FNV-1a de 32 bits: o sorteio diário sai daqui, sem guardar nada.
function hash(text) {
  let h = 0x811c9dc5
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i)
    h = Math.imul(h, 0x01000193) >>> 0
  }
  return h
}

// As diárias da conta no dia: as `DAILY_COUNT` de menor hash. Estável no dia,
// muda no seguinte e é diferente entre contas, sem guardar o sorteio.
// ponytail: ligar ou desligar uma diária no admin pode trocar o sorteio do dia
// de quem já está jogando; o progresso das que ficaram continua.
function dailyPick(pool, userId, day) {
  const score = (m) => hash(userId + "|" + day + "|" + m.key)
  return pool.slice().sort((a, b) => score(a) - score(b) || (a.key < b.key ? -1 : 1)).slice(0, DAILY_COUNT)
}

// As missões valendo agora para a conta, cada uma com o período em que conta
// (`d:<dia>`, `perm` ou `e:<evento>`) e, se for de evento, o evento.
function liveMissions(missions, events, userId, day, nowMs) {
  const live = []
  const daily = missions.filter((m) => m.active && m.track === "daily")
  for (const m of dailyPick(daily, userId, day)) {
    live.push(Object.assign({}, m, { period: "d:" + day }))
  }
  for (const m of missions) {
    if (m.active && m.track === "perm") {
      live.push(Object.assign({}, m, { period: "perm" }))
    }
  }
  const open = events.filter((e) => e.starts <= nowMs && nowMs < e.ends)
  for (const m of missions) {
    const event = open.find((e) => e.id === m.event)
    if (m.active && m.track === "event" && event) {
      live.push(Object.assign({}, m, { period: "e:" + event.key, eventKey: event.key }))
    }
  }
  return live
}

function slot(state, period) {
  if (!state[period]) {
    state[period] = { p: {}, c: [], g: [] }
  }
  return state[period]
}

function progressOf(state, m) {
  const s = state[m.period]
  return s && s.p[m.key] ? s.p[m.key] : 0
}

function claimedOf(state, m) {
  const s = state[m.period]
  return Boolean(s && s.c.includes(m.key))
}

// Uma partida terminada avança as missões que casam. Devolve as chaves que
// acabaram de completar. Mexe em `state`.
function advance(state, live, game, result) {
  const done = []
  for (const m of live) {
    const s = slot(state, m.period)
    let n = 0
    if (m.kind === "variety") {
      if (!s.g.includes(game)) {
        s.g.push(game)
      }
      n = s.g.length
    } else {
      if ((m.game && m.game !== game) || (m.kind === "win" && result !== "win")) {
        continue
      }
      n = progressOf(state, m) + 1
    }
    const before = progressOf(state, m)
    s.p[m.key] = Math.min(m.target, n)
    if (before < m.target && s.p[m.key] >= m.target) {
      done.push(m.key)
    }
  }
  return done
}

// Tira do estado os períodos que não valem mais (dia passado, evento acabado).
function prune(state, live) {
  const keep = {}
  for (const m of live) {
    if (state[m.period]) {
      keep[m.period] = state[m.period]
    }
  }
  if (state.perm) {
    keep.perm = state.perm
  }
  return keep
}

// O que o app vê de cada missão.
function view(state, live) {
  return live.map((m) => ({
    key: m.key,
    track: m.track,
    event: m.eventKey || "",
    kind: m.kind,
    game: m.game,
    target: m.target,
    title: m.title,
    reward_coins: m.reward_coins,
    reward_item: m.reward_item,
    progress: progressOf(state, m),
    claimed: claimedOf(state, m),
  }))
}

// Missões e eventos lidos do banco, no formato das funções de cima.
function load(app) {
  const missions = app.findAllRecords("missions").map((r) => ({
    key: r.getString("key"),
    track: r.getString("track"),
    event: r.getString("event"),
    kind: r.getString("kind"),
    game: r.getString("game"),
    target: r.getInt("target"),
    title: r.getString("title"),
    reward_coins: r.getInt("reward_coins"),
    reward_item: r.getString("reward_item"),
    active: r.getBool("active"),
  }))
  const events = app.findAllRecords("events").map((r) => ({
    id: r.id,
    key: r.getString("key"),
    name: r.getString("name"),
    starts: r.getDateTime("starts").unix() * 1000,
    ends: r.getDateTime("ends").unix() * 1000,
  }))
  return { missions, events }
}

// O problema de uma missão salva pelo admin, ou "" se ela está certa.
function missionProblem(m, shopItems) {
  if ((m.track === "event") !== (m.event !== "")) {
    return "Missão de evento precisa de evento, e só ela."
  }
  if (m.reward_item !== "" && !shopItems.includes(m.reward_item)) {
    return "reward_item não está em shop_items: " + m.reward_item
  }
  if (m.reward_coins === 0 && m.reward_item === "") {
    return "A missão precisa pagar moedas ou um item."
  }
  return ""
}

module.exports = { DAILY_COUNT, hash, dailyPick, liveMissions, advance, prune, view, progressOf, claimedOf, slot, load, missionProblem }
