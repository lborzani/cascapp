// Comum às rotas da conversa. Sem `.pb.js` no nome: só entra por `require`.

// Quantas mensagens a rota devolve, e quantas o par guarda.
const PAGE = 50
const KEEP = 200
// Por conta, em qualquer conversa. Ninguém digita mais rápido que isso.
const PER_MINUTE = 20
const TEXT_LIMIT = 120
// O tamanho de `ChatLog.EMOTES` no app. Lá a lista só cresce no fim; crescer
// aqui junto.
const EMOTE_COUNT = 8

// A mesma limpeza de `ChatLog.clean` no app: controles e espaços viram um
// espaço só, marcas de direção do texto saem, e corta em 120 caracteres (por
// caractere, e não por unidade UTF-16, para não partir um emoji).
function cleanText(raw) {
  if (typeof raw !== "string") return ""
  const out = raw
    .slice(0, TEXT_LIMIT * 4)
    .replace(/[؜‎‏‪-‮⁦-⁩]/g, "")
    .replace(/[\u0000- \u007F-   ]+/g, " ")
    .trim()
  return Array.from(out).slice(0, TEXT_LIMIT).join("").trim()
}

// Os campos a gravar, ou `null` quando a mensagem não vale.
function validate(body) {
  switch (body.kind) {
    case "text": {
      const text = cleanText(body.text)
      return text ? { kind: "text", text } : null
    }
    case "emote": {
      const emote = body.emote
      return Number.isInteger(emote) && emote >= 0 && emote < EMOTE_COUNT ? { kind: "emote", emote } : null
    }
    case "invite": {
      const game = String(body.game || "")
      const room = String(body.room || "")
      return /^[a-z_]{1,20}$/.test(game) && /^[A-Z0-9]{4,12}$/.test(room) ? { kind: "invite", game, room } : null
    }
  }
  return null
}

function toJson(row) {
  return {
    id: row.id,
    from: row.getString("from"),
    kind: row.getString("kind"),
    text: row.getString("text"),
    emote: row.getInt("emote"),
    game: row.getString("game"),
    room: row.getString("room"),
    at: Math.floor(row.getDateTime("created").unix()),
  }
}

// O par guarda as `KEEP` mais novas; as de antes saem.
function trim(app, a, b) {
  const old = app.findRecordsByFilter(
    "direct_messages",
    "(from = {:a} && to = {:b}) || (from = {:b} && to = {:a})",
    "-created", 100, KEEP, { a, b }
  )
  for (const row of old) app.delete(row)
}

module.exports = { PAGE, KEEP, PER_MINUTE, EMOTE_COUNT, cleanText, validate, toJson, trim }
