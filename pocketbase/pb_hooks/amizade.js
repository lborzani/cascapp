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

module.exports = { MAX_PENDING, areFriends, findRequest, befriend }
