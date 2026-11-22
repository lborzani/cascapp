// Comum às rotas da loja (ver `pb_migrations/1763300000_loja.js`). Sem
// `.pb.js` no nome: não é carregado sozinho, só por `require`. As funções de
// cima não usam nada do PocketBase, e `pocketbase/loja.test.js` as testa no Node.

// O preço de cada item pago. Item que não está aqui é grátis (as cores, por
// exemplo) e pode ser equipado sem compra. O catálogo visual (nome, arquivo,
// tipo) mora no app, em `core/cosmetics.gd`; o preço mora só aqui.
const PRICES = {
  ball_galaxy: 400,
  ball_flames: 300,
  ball_ocean: 250,
  ball_melon: 200,
  ball_wood: 150,
  ball_checker: 200,
  board_wood: 200,
  board_marble: 300,
  board_tournament: 150,
  board_ocean: 200,
  board_neon: 300,
  board_candy: 250,
  finish_wood: 200,
  finish_marble: 250,
  finish_metal: 350,
  finish_neon: 300,
  finish_gems: 350,
}

const DAILY = 50
// Por partida terminada contra bot ou online, pelo desfecho de quem pede.
const REWARDS = { win: 25, draw: 15, loss: 10 }
// ponytail: o app conta o próprio desfecho e o servidor confia, só limitando o
// total do dia. Para fechar de vez, o relay arbitra o prêmio online, como já
// faz com o Elo do xadrez (`relay/src/ratings.ts`).
const REWARD_CAP = 300
const GAMES = ["chess", "checkers", "battleship", "ludo", "monopoly", "uno", "pool", "bowling"]
const LOOK_SLOTS = 12

// O dia de Brasília (UTC-3, sem horário de verão desde 2019), "AAAA-MM-DD".
function brDay(ms) {
  return new Date(ms - 3 * 3600 * 1000).toISOString().slice(0, 10)
}

// Quanto pagar por uma partida, dado o que já foi pago hoje. `null` quando o
// pedido é inválido.
function rewardFor(game, result, earnedToday) {
  if (!GAMES.includes(game) || !(result in REWARDS)) {
    return null
  }
  return Math.max(0, Math.min(REWARDS[result], REWARD_CAP - earnedToday))
}

// O primeiro item pago do visual que não está em `owned`, ou "" quando o
// visual é válido. `null` quando o formato está errado.
function lookProblem(look, owned) {
  if (look === null || typeof look !== "object" || Array.isArray(look)) {
    return null
  }
  const slots = Object.keys(look)
  if (slots.length > LOOK_SLOTS) {
    return null
  }
  for (const slot of slots) {
    const item = look[slot]
    if (typeof item !== "string" || slot.length > 20 || item.length > 40) {
      return null
    }
    if (item in PRICES && !owned.includes(item)) {
      return item
    }
  }
  return ""
}

// Um campo JSON do registro, já decodificado.
function jsonOf(record, name, fallback) {
  const raw = record.getString(name)
  if (raw === "" || raw === "null") {
    return fallback
  }
  try {
    return JSON.parse(raw)
  } catch (_) {
    return fallback
  }
}

function wallet(record) {
  return {
    coins: record.getInt("coins"),
    owned: jsonOf(record, "owned", []),
    look: jsonOf(record, "look", {}),
    // Para o app ignorar a resposta que chega depois de uma mais nova.
    updated: record.getString("updated"),
  }
}

module.exports = { PRICES, DAILY, REWARDS, REWARD_CAP, GAMES, brDay, rewardFor, lookProblem, jsonOf, wallet }
