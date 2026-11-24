// Comum às rotas dos presentes (ver `pb_migrations/1764200000_presentes.js`).
// Sem `.pb.js` no nome: só entra por `require`. As funções de decisão são puras
// e `pocketbase/presentes.test.js` as testa no Node.

// O presentinho do dia: quanto vale e quantos uma conta recebe por dia. O teto
// de recebidos é o que segura contas falsas alimentando uma conta só.
const DAILY_COINS = 10
const MAX_RECEIVED = 5
// Quantos presentes fechados a caixa devolve de uma vez.
const INBOX = 50

// `{status, message}` quando o presente de item não pode sair, ou `null`.
// `price` é `undefined` para item que não está à venda (exclusivo, inativo ou
// inexistente).
function itemProblem(price, recipientOwns, coins) {
  if (price === undefined) {
    return { status: 404, message: "Esse item não está à venda." }
  }
  if (recipientOwns) {
    return { status: 409, message: "Seu amigo já tem esse item." }
  }
  if (coins < price) {
    return { status: 402, message: "Moedas insuficientes." }
  }
  return null
}

// `{status, message}` quando o presentinho do dia não pode sair, ou `null`.
function dailyProblem(sentToThemToday, theyReceivedToday) {
  if (sentToThemToday) {
    return { status: 409, message: "Você já mandou o presentinho de hoje para esse amigo." }
  }
  if (theyReceivedToday >= MAX_RECEIVED) {
    return { status: 429, message: "Seu amigo já ganhou presentinhos demais hoje." }
  }
  return null
}

// O que o app vê de um presente fechado.
function toJson(row, sender) {
  return {
    id: row.id,
    from: { id: sender.id, name: sender.getString("name") },
    item: row.getString("item"),
    coins: row.getInt("coins"),
    created: Math.floor(row.getDateTime("created").unix()),
  }
}

module.exports = { DAILY_COINS, MAX_RECEIVED, INBOX, itemProblem, dailyProblem, toJson }
