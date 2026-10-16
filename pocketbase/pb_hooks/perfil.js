// Comum aos hooks do perfil. Sem `.pb.js` no nome: não é carregado sozinho, só
// por `require`.

// Sem 0/O nem 1/I/L, que se confundem lidos em voz alta ou numa tela pequena.
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const START_ELO = 1200

function newFriendCode(app) {
  // 31^6 ≈ 900 milhões de códigos: a repetição é rara, mas o índice único
  // recusaria o registro inteiro se ela acontecesse.
  for (;;) {
    const code = $security.randomStringWithAlphabet(6, ALPHABET)
    if (app.countRecords("users", $dbx.hashExp({ friend_code: code })) === 0) {
      return code
    }
  }
}

// O que uma conta pode ver de outra. O e-mail nunca.
function publicProfile(record) {
  return {
    id: record.id,
    name: record.getString("name"),
    avatar: record.getString("avatar"),
    friend_code: record.getString("friend_code"),
    elo_chess: record.getInt("elo_chess"),
    games_chess: record.getInt("games_chess"),
  }
}

module.exports = { START_ELO, newFriendCode, publicProfile }
