// As regras puras da conta protegida por e-mail (`pb_hooks/conta.js`), sem
// PocketBase:
//
//   node --test pocketbase/conta.test.js
//
// As rotas e a troca de credencial são cobertas pelo `tests/recovery_probe.gd`
// contra um PocketBase de verdade.
const test = require("node:test")
const assert = require("node:assert")
const conta = require("./pb_hooks/conta.js")

test("e-mail: normaliza e confere o formato", () => {
  assert.strictEqual(conta.normalizeEmail("  Lucas@Gmail.COM "), "lucas@gmail.com")
  assert.ok(conta.validEmail("lucas@gmail.com"))
  assert.ok(!conta.validEmail("lucas@gmail"))
  assert.ok(!conta.validEmail("lu cas@gmail.com"))
  assert.ok(!conta.validEmail(""))
  assert.ok(!conta.validEmail("abc@anon.cascapp.invalid"), "o e-mail sintético não protege nada")
})

test("e-mail mascarado", () => {
  assert.strictEqual(conta.maskEmail("lucas@gmail.com"), "l***@gmail.com")
  assert.strictEqual(conta.maskEmail("x@y.com"), "x***@y.com")
  assert.strictEqual(conta.maskEmail("semarroba"), "")
})

test("envios: 3 a cada 15 minutos e 10 por dia", () => {
  const now = 100 * conta.DAY_MS
  const min = 60 * 1000
  assert.ok(conta.canSend([], now))
  assert.ok(conta.canSend([now - min, now - 2 * min], now))
  assert.ok(!conta.canSend([now - min, now - 2 * min, now - 3 * min], now))
  assert.ok(conta.canSend([now - 16 * min, now - 17 * min, now - 18 * min], now), "a janela anda")
  const spread = Array.from({ length: 10 }, (_, i) => now - (i + 1) * 60 * min)
  assert.ok(!conta.canSend(spread, now), "teto do dia")
  assert.ok(conta.canSend(spread.map((at) => at - conta.DAY_MS), now), "e o dia anda")
})

test("código: certo, errado, vencido e travado", () => {
  const now = 1000000
  const entry = { code_hash: "h", sent_at: now - 1000, attempts: 0 }
  assert.strictEqual(conta.checkCode(entry, "h", now), "ok")
  assert.strictEqual(conta.checkCode(entry, "x", now), "wrong")
  assert.strictEqual(conta.checkCode({ ...entry, sent_at: now - conta.CODE_TTL_MS - 1 }, "h", now), "expired")
  assert.strictEqual(conta.checkCode({ ...entry, attempts: conta.MAX_ATTEMPTS }, "h", now), "locked")
  assert.strictEqual(conta.checkCode({ ...entry, attempts: conta.MAX_ATTEMPTS - 1 }, "h", now), "ok")
})

test("o e-mail leva o código no assunto e no corpo", () => {
  const mail = conta.mailBody("123456", "recover")
  assert.ok(mail.subject.includes("123456"))
  assert.ok(mail.text.includes("recuperar"))
  assert.ok(mail.html.includes("123456"))
})
