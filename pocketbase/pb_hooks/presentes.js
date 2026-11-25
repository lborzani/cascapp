// Comum às rotas dos presentes (ver `pb_migrations/1764200000_presentes.js`).
// Sem `.pb.js` no nome: só entra por `require`. As funções de decisão são puras
// e `pocketbase/presentes.test.js` as testa no Node.

// O presentinho do dia: quanto vale e quantos uma conta recebe por dia. O teto
// de recebidos é o que segura contas falsas alimentando uma conta só.
const DAILY_COINS = 10
const MAX_RECEIVED = 5
// Quantos presentes fechados a caixa devolve de uma vez.
const INBOX = 50
// Quantos itens cabem num kit (`1764500000_presente_kit.js`).
const MAX_KIT = 20
// O kit de agradecimento aos testadores (`1764600000_testador.js`), que sai
// sozinho quando o admin liga `tester` na conta.
const TESTER_KIT = ["frame_pioneer", "banner_pioneer", "title_pioneer", "name_pioneer", "ball_pioneer", "cue_pioneer", "finish_pioneer", "board_pioneer", "token_pioneer", "deck_pioneer"]
const TESTER_MESSAGE = "Valeu por construir o cascapp comigo! Isto aqui é só de quem esteve desde o começo."

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

// O valor cru do campo `items` de um kit (texto JSON), já lido: `null` quando
// vazio, `undefined` quando não é JSON.
function parseItems(raw) {
  if (raw === "" || raw === "null") {
    return null
  }
  try {
    return JSON.parse(raw)
  } catch (_) {
    return undefined
  }
}

// O que há de errado no `items` de um kit que o admin salva, ou "". `shop` são
// os ids de `shop_items`.
function kitProblem(items, shop) {
  if (items === null) {
    return ""
  }
  if (!Array.isArray(items)) {
    return "items precisa ser uma lista de ids, como [\"frame_pioneer\"]."
  }
  if (items.length > MAX_KIT) {
    return `Um kit leva no máximo ${MAX_KIT} itens.`
  }
  for (const item of items) {
    if (typeof item !== "string" || !shop.includes(item)) {
      return `Item fora do shop_items: ${JSON.stringify(item)}.`
    }
  }
  return ""
}

// `kitProblem` de um registro de `gifts`, contra o catálogo do banco.
function recordKitProblem(app, record) {
  const shop = app.findAllRecords("shop_items").map((row) => row.getString("item"))
  return kitProblem(parseItems(record.getString("items")), shop)
}

// Os itens de um kit para entregar: só ids em texto, sem repetir.
function kitItems(items) {
  if (!Array.isArray(items)) {
    return []
  }
  return items.filter((item, i) => typeof item === "string" && item !== "" && item.length <= 40 && items.indexOf(item) === i)
}

// O `owned` depois de abrir um kit: o que já era, mais o que faltava.
function withItems(owned, items) {
  return owned.concat(items.filter((item) => !owned.includes(item)))
}

// O texto da notificação de um kit: com remetente, como o presente de amigo;
// sem (o kit de testador, que sai "do cascapp"), na voz do app.
function kitPushText(from) {
  return from ? "Te mandou um presente 🎁" : "Você ganhou um presente 🎁"
}

// Se a conta deve receber o kit de testador agora: é testador e ainda não ganhou.
function owesTesterKit(tester, alreadySent) {
  return tester === true && alreadySent !== true
}

// O que o app vê de um presente fechado. Sem `sender` (o kit de testador sai
// sem remetente) vem `id` vazio e o nome "cascapp": o app mostra "Do cascapp",
// e o de antes do kit, "De cascapp", em vez de quebrar.
function toJson(row, sender) {
  return {
    id: row.id,
    from: sender ? { id: sender.id, name: sender.getString("name") } : { id: "", name: "cascapp" },
    item: row.getString("item"),
    coins: row.getInt("coins"),
    items: kitItems(parseItems(row.getString("items"))),
    message: row.getString("message"),
    created: Math.floor(row.getDateTime("created").unix()),
  }
}

module.exports = {
  DAILY_COINS, MAX_RECEIVED, INBOX, MAX_KIT, TESTER_KIT, TESTER_MESSAGE,
  itemProblem, dailyProblem, parseItems, kitProblem, recordKitProblem, kitItems, withItems, owesTesterKit, kitPushText, toJson,
}
