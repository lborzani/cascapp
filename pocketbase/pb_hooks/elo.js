// O cálculo do Elo. Sem `.pb.js` no nome: só entra por `require`.

const START_ELO = 1200
// K maior nas primeiras partidas, para a conta nova chegar logo perto do nível
// de verdade; depois, menor, para uma partida ruim não desfazer um mês. É a
// ideia da FIDE com números redondos.
const NEW_GAMES = 20
const K_NEW = 40
const K = 20

function ratingOf(record) {
  const rating = record.getInt("elo_chess")
  // Conta de antes do perfil público (Elo 0 no banco) começa no inicial.
  return rating > 0 ? rating : START_ELO
}

// Quanto `player` ganha (ou perde, negativo) com `score` (1, 0.5 ou 0) contra
// `opponent`. Cada um usa o próprio K, então a soma nem sempre é zero.
function delta(player, opponent, score) {
  const expected = 1 / (1 + Math.pow(10, (ratingOf(opponent) - ratingOf(player)) / 400))
  const k = player.getInt("games_chess") < NEW_GAMES ? K_NEW : K
  return Math.round(k * (score - expected))
}

function replyOf(game) {
  return {
    white: { elo: game.getInt("white_elo"), delta: game.getInt("white_delta") },
    black: { elo: game.getInt("black_elo"), delta: game.getInt("black_delta") },
  }
}

module.exports = { START_ELO, ratingOf, delta, replyOf }
