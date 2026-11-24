// Regras puras da conta protegida por e-mail, sem PocketBase, para o
// `pocketbase/conta.test.js` rodar no Node.

// O código vale 10 minutos e aceita 5 tentativas.
const CODE_TTL_MS = 10 * 60 * 1000
const MAX_ATTEMPTS = 5
// Envios por e-mail: 3 a cada 15 minutos e 10 por dia. O teto do dia segura
// quem tenta adivinhar o código da conta de outro: 10 envios × 5 tentativas
// são 50 palpites por dia num milhão de códigos.
const SEND_WINDOW_MS = 15 * 60 * 1000
const SEND_PER_WINDOW = 3
const SEND_PER_DAY = 10
const DAY_MS = 24 * 60 * 60 * 1000
const PURPOSES = ["protect", "recover"]
// O domínio das contas anônimas (`Account.EMAIL_DOMAIN` no app).
const ANON_DOMAIN = "anon.cascapp.invalid"

function normalizeEmail(raw) {
  return String(raw || "").trim().toLowerCase()
}

// Uma checagem de formato, e não de existência: quem confirma que o e-mail
// existe é o código chegando nele.
function validEmail(email) {
  return email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && !email.endsWith("@" + ANON_DOMAIN)
}

// "lucas@gmail.com" → "l***@gmail.com". O app mostra assim, para quem pega o
// celular de outro não ler o e-mail inteiro.
function maskEmail(email) {
  const at = email.indexOf("@")
  if (at < 1) {
    return ""
  }
  return email[0] + "***" + email.slice(at)
}

// `sent` são os `sent_at` dos envios anteriores para o e-mail. Devolve se
// mais um envio cabe agora.
function canSend(sent, now) {
  const recent = sent.filter((at) => now - at < SEND_WINDOW_MS).length
  const today = sent.filter((at) => now - at < DAY_MS).length
  return recent < SEND_PER_WINDOW && today < SEND_PER_DAY
}

// `entry` é o último código mandado, `{code_hash, sent_at, attempts}`, e
// `hash` o hash do código digitado. Devolve "ok", "expired", "locked" ou
// "wrong". Quem chama soma a tentativa quando é "wrong".
function checkCode(entry, hash, now) {
  if (now - entry.sent_at > CODE_TTL_MS) {
    return "expired"
  }
  if (entry.attempts >= MAX_ATTEMPTS) {
    return "locked"
  }
  return entry.code_hash === hash ? "ok" : "wrong"
}

function mailBody(code, purpose) {
  const action = purpose === "recover" ? "recuperar sua conta" : "proteger sua conta"
  return {
    subject: `Seu código do Cascapp: ${code}`,
    text: `Seu código para ${action} no Cascapp é ${code}.\n\nEle vale por 10 minutos. Se não foi você que pediu, ignore este e-mail.`,
    html: `<p>Seu código para ${action} no Cascapp é:</p>`
      + `<p style="font-size:32px;font-weight:bold;letter-spacing:6px">${code}</p>`
      + `<p>Ele vale por 10 minutos. Se não foi você que pediu, ignore este e-mail.</p>`,
  }
}

module.exports = {
  CODE_TTL_MS, MAX_ATTEMPTS, SEND_PER_WINDOW, SEND_PER_DAY, DAY_MS, PURPOSES,
  normalizeEmail, validEmail, maskEmail, canSend, checkCode, mailBody,
}
