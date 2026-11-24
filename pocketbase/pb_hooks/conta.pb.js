/// <reference path="../pb_data/types.d.ts" />

// Conta protegida por e-mail (ver `pb_migrations/1763900000_conta_email.js`).
//
//   POST /api/cascapp/email/start    {email, purpose}         manda um código
//   POST /api/cascapp/email/protect  {code}                   liga o e-mail à conta
//   POST /api/cascapp/email/recover  {email, code, password}  volta para a conta antiga
//
// Todas pedem conta: o app sempre tem a dele, a anônima, criada na abertura.
//
// Recuperar não entra na conta antiga: ela passa a aceitar a credencial do
// aparelho novo. O aparelho novo já tem uma conta vazia, criada sozinha na
// abertura, com o e-mail sintético dele. A rota apaga essa conta e grava o
// e-mail sintético e a senha dela na conta antiga. Na próxima entrada, o
// `sign_in` de sempre cai na conta antiga, e a forma de entrar não muda.
//
// Cada handler roda num contexto isolado: o que é comum mora em `conta.js` e
// entra por `require` dentro do handler.

routerAdd("POST", "/api/cascapp/email/start", (e) => {
  const conta = require(`${__hooks}/conta.js`)
  const body = e.requestInfo().body
  const email = conta.normalizeEmail(body.email)
  const purpose = String(body.purpose || "")
  if (!conta.validEmail(email) || !conta.PURPOSES.includes(purpose)) {
    return e.json(400, { message: "E-mail inválido." })
  }
  let target = e.auth.id
  if (purpose === "recover") {
    let owner = null
    try {
      owner = e.app.findFirstRecordByData("users", "contact_email", email)
    } catch (_) {}
    if (owner === null) {
      // A mesma resposta de quando o código sai, e nenhum e-mail sai: quem
      // pergunta não descobre quais e-mails têm conta.
      return e.json(200, {})
    }
    target = owner.id
  }
  // Proteger com um e-mail que já protege outra conta só é recusado na
  // confirmação, pelo mesmo motivo: só o dono do e-mail fica sabendo.

  const now = Date.now()
  e.app.db()
    .newQuery("DELETE FROM email_codes WHERE email = {:email} AND sent_at < {:before}")
    .bind({ email: email, before: now - conta.DAY_MS })
    .execute()
  const past = e.app.findRecordsByFilter("email_codes", "email = {:email}", "", 0, 0, { email: email })
  const sent = []
  for (let i = 0; i < past.length; i++) {
    sent.push(past[i].getInt("sent_at"))
  }
  if (!conta.canSend(sent, now)) {
    return e.json(429, { message: "Muitos códigos para este e-mail. Espere um pouco." })
  }

  const code = $security.randomStringWithAlphabet(6, "0123456789")
  const entry = new Record(e.app.findCollectionByNameOrId("email_codes"))
  entry.set("email", email)
  entry.set("purpose", purpose)
  entry.set("code_hash", $security.sha256(email + ":" + code))
  entry.set("user", target)
  entry.set("sent_at", now)
  entry.set("attempts", 0)
  e.app.save(entry)

  if ($os.getenv("CASCAPP_MAIL_CAPTURE") === "1") {
    // ponytail: só nos testes locais, que não têm SMTP; a rota de leitura
    // abaixo só existe com a mesma variável.
    e.app.store().set("mail:" + email, code)
    return e.json(200, {})
  }
  const mail = conta.mailBody(code, purpose)
  const settings = e.app.settings()
  try {
    e.app.newMailClient().send(new MailerMessage({
      from: { address: settings.meta.senderAddress, name: settings.meta.senderName },
      to: [{ address: email }],
      subject: mail.subject,
      text: mail.text,
      html: mail.html,
    }))
  } catch (err) {
    e.app.delete(entry)
    e.app.logger().error("email do código não saiu", "error", String(err))
    return e.json(502, { message: "O e-mail não saiu. Tente de novo." })
  }
  return e.json(200, {})
}, $apis.requireAuth("users"))

routerAdd("POST", "/api/cascapp/email/protect", (e) => {
  const conta = require(`${__hooks}/conta.js`)
  const body = e.requestInfo().body
  const found = e.app.findRecordsByFilter(
    "email_codes", "user = {:user} && purpose = 'protect'", "-sent_at", 1, 0, { user: e.auth.id }
  )
  if (found.length === 0) {
    return e.json(400, { message: "Peça um código primeiro.", reason: "missing" })
  }
  const entry = found[0]
  const email = entry.getString("email")
  const verdict = conta.checkCode(
    { code_hash: entry.getString("code_hash"), sent_at: entry.getInt("sent_at"), attempts: entry.getInt("attempts") },
    $security.sha256(email + ":" + String(body.code || "").trim()),
    Date.now()
  )
  if (verdict === "wrong") {
    entry.set("attempts", entry.getInt("attempts") + 1)
    e.app.save(entry)
  }
  if (verdict !== "ok") {
    return e.json(400, { message: "Código inválido.", reason: verdict })
  }

  try {
    const user = e.app.findRecordById("users", e.auth.id)
    user.set("contact_email", email)
    e.app.save(user)
  } catch (_) {
    // O índice único: outra conta já tem este e-mail.
    return e.json(409, { message: "Este e-mail já protege outra conta." })
  }
  e.app.db().newQuery("DELETE FROM email_codes WHERE email = {:email}").bind({ email: email }).execute()
  return e.json(200, { contact_email: email })
}, $apis.requireAuth("users"))

routerAdd("POST", "/api/cascapp/email/recover", (e) => {
  const conta = require(`${__hooks}/conta.js`)
  const body = e.requestInfo().body
  const email = conta.normalizeEmail(body.email)
  const password = String(body.password || "")
  // A senha prova que quem pede é o aparelho dono desta conta vazia, e não
  // alguém com o token dela. É ela que a conta antiga vai aceitar depois.
  if (!e.auth.validatePassword(password)) {
    return e.json(403, { message: "Credencial deste aparelho recusada." })
  }
  const found = e.app.findRecordsByFilter(
    "email_codes", "email = {:email} && purpose = 'recover'", "-sent_at", 1, 0, { email: email }
  )
  if (found.length === 0) {
    return e.json(400, { message: "Código inválido.", reason: "missing" })
  }
  const entry = found[0]
  const verdict = conta.checkCode(
    { code_hash: entry.getString("code_hash"), sent_at: entry.getInt("sent_at"), attempts: entry.getInt("attempts") },
    $security.sha256(email + ":" + String(body.code || "").trim()),
    Date.now()
  )
  if (verdict === "wrong") {
    entry.set("attempts", entry.getInt("attempts") + 1)
    e.app.save(entry)
  }
  if (verdict !== "ok") {
    return e.json(400, { message: "Código inválido.", reason: verdict })
  }
  const targetId = entry.getString("user")
  if (targetId === e.auth.id) {
    return e.json(400, { message: "Esta já é a conta deste aparelho.", reason: "same" })
  }
  try {
    if (e.app.findRecordById("users", targetId).getString("contact_email") !== email) {
      throw new Error("o e-mail mudou")
    }
  } catch (_) {
    // A conta antiga sumiu, ou não é mais protegida por este e-mail.
    return e.json(400, { message: "Código inválido.", reason: "missing" })
  }

  e.app.runInTransaction((tx) => {
    const mine = tx.findRecordById("users", e.auth.id)
    const old = tx.findRecordById("users", targetId)
    const synthetic = mine.email()
    // A conta vazia sai antes, para o e-mail sintético dela ficar livre. O
    // que ela tinha (partidas, códigos) vai junto, pelo `cascadeDelete`.
    tx.delete(mine)
    old.setEmail(synthetic)
    old.setPassword(password)
    tx.save(old)
    tx.db().newQuery("DELETE FROM email_codes WHERE email = {:email}").bind({ email: email }).execute()
  })
  return e.json(200, {})
}, $apis.requireAuth("users"))

if ($os.getenv("CASCAPP_MAIL_CAPTURE") === "1") {
  // O último código mandado para o e-mail, para o `tests/recovery_probe.gd`.
  routerAdd("GET", "/api/cascapp/test/last-code/{email}", (e) => {
    const code = e.app.store().get("mail:" + e.request.pathValue("email"))
    return code ? e.json(200, { code: code }) : e.json(404, {})
  })
}
