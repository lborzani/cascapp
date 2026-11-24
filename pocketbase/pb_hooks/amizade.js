// Comum às rotas de amigos. Sem `.pb.js` no nome: só entra por `require`.

// Quantos pedidos uma conta pode ter esperando resposta. Ninguém precisa de
// mais para chamar os amigos de verdade; quem passa disso está varrendo códigos.
const MAX_PENDING = 50

function areFriends(app, a, b) {
  try {
    app.findFirstRecordByFilter("friendships", "owner = {:a} && friend = {:b}", { a, b })
    return true
  } catch (_) {
    return false
  }
}

function findRequest(app, from, to) {
  try {
    return app.findFirstRecordByFilter("friend_requests", "from = {:from} && to = {:to}", { from, to })
  } catch (_) {
    return null
  }
}

// A amizade nos dois sentidos, e os pedidos entre os dois somem. Dentro de uma
// transação (`tx`): ou tudo, ou nada.
function befriend(tx, a, b) {
  const collection = tx.findCollectionByNameOrId("friendships")
  for (const [owner, friend] of [[a, b], [b, a]]) {
    if (!areFriends(tx, owner, friend)) {
      const row = new Record(collection)
      row.set("owner", owner)
      row.set("friend", friend)
      tx.save(row)
    }
    const pending = findRequest(tx, owner, friend)
    if (pending) tx.delete(pending)
  }
}

// `owner` bloqueou `blocked` (`pb_migrations/1764300000_bloqueios.js`).
function findBlock(app, owner, blocked) {
  try {
    return app.findFirstRecordByFilter("blocks", "owner = {:owner} && blocked = {:blocked}", { owner, blocked })
  } catch (_) {
    return null
  }
}

// Desfaz a amizade nos dois sentidos e some com os pedidos entre os dois.
// Dentro de uma transação (`tx`).
function unfriend(tx, a, b) {
  for (const [name, x, y] of [["friendships", "owner", "friend"], ["friend_requests", "from", "to"]]) {
    const filter = `(${x} = {:a} && ${y} = {:b}) || (${x} = {:b} && ${y} = {:a})`
    for (const row of tx.findRecordsByFilter(name, filter, "", 2, 0, { a, b })) tx.delete(row)
  }
}

// `owner` silenciou `friend`: as mensagens de `friend` não viram notificação.
function isMuted(app, owner, friend) {
  try {
    return app.findFirstRecordByFilter("friendships", "owner = {:owner} && friend = {:friend}", { owner, friend }).getBool("muted")
  } catch (_) {
    return false
  }
}

module.exports = { MAX_PENDING, areFriends, findRequest, befriend, findBlock, unfriend, isMuted }
