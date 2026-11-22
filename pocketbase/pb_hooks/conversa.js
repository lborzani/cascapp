// Comum às rotas da conversa. Sem `.pb.js` no nome: só entra por `require`.

// Quantas mensagens a rota devolve, e quantas o par guarda.
const PAGE = 50
const KEEP = 200
// Por conta, em qualquer conversa. Ninguém digita mais rápido que isso.
const PER_MINUTE = 20
const TEXT_LIMIT = 120
// A mesma lista de `ChatLog.EMOTES` no app. Lá ela só cresce no fim; crescer
// aqui junto.
const EMOTES = ["👍", "😂", "😮", "😢", "😡", "🔥", "👏", "🤔"]
const EMOTE_COUNT = EMOTES.length
// Quantos aparelhos de uma conta recebem a notificação.
const MAX_DEVICES = 10

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

// O texto da notificação: a mensagem, o emoji ou o convite.
function preview(row) {
  switch (row.getString("kind")) {
    case "emote":
      return EMOTES[row.getInt("emote")] || "?"
    case "invite":
      return "Te chamou para jogar"
  }
  return row.getString("text")
}

// Avisa os aparelhos de quem recebeu, pelo serviço `push` do compose. Sem
// segredo configurado (teste local, servidor antigo), não faz nada. Tokens que
// o Firebase diz que morreram saem da coleção. Qualquer erro aqui fica aqui: a
// mensagem já foi gravada, e a notificação é só um aviso.
// ponytail: síncrono dentro do POST da mensagem (~300 ms do FCM a mais na
// resposta); fila à parte se isso pesar.
function notify(app, row) {
  const secret = $os.getenv("CASCAPP_PUSH_SECRET")
  if (!secret) return
  try {
    const to = row.getString("to")
    const tokens = app.findRecordsByFilter("push_tokens", "owner = {:to}", "-updated", MAX_DEVICES, 0, { to })
    if (tokens.length === 0) return
    const sender = app.findRecordById("users", row.getString("from"))
    const reply = $http.send({
      url: ($os.getenv("CASCAPP_PUSH_URL") || "http://push:8095") + "/send",
      method: "POST",
      headers: { "Content-Type": "application/json", "x-push-secret": secret },
      body: JSON.stringify({
        tokens: tokens.map((t) => t.getString("token")),
        title: sender.getString("name") || "Um amigo",
        body: preview(row),
        friend: sender.id,
      }),
      timeout: 5,
    })
    const dropped = reply.statusCode === 200 && reply.json && Array.isArray(reply.json.dropped) ? reply.json.dropped : []
    for (const t of tokens) {
      if (dropped.includes(t.getString("token"))) app.delete(t)
    }
  } catch (error) {
    console.log("push falhou:", String(error))
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

module.exports = { PAGE, KEEP, PER_MINUTE, EMOTES, EMOTE_COUNT, cleanText, validate, toJson, trim, preview, notify }
