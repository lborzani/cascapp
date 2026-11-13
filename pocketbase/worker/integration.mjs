// Integração do worker com um PocketBase de teste vazio (as migrations do repo)
// e o Stockfish de verdade. Roda dentro da imagem do worker; quem sobe o
// PocketBase e o superusuário é o `integration.sh`.
//
// Partida: o mate do pastor que não aconteceu (a mesma do `stockfish_probe`).
// Depois de 3...Cf6 o melhor das brancas é Dxf7#, mate em 1.
import assert from 'node:assert/strict';
import { config, run } from './worker.mjs';

const GAME = 'e2e4 e7e5 f1c4 b8c6 d1h5 g8f6 d2d3';

async function call(method, path, body, token = '') {
  const response = await fetch(config.pbUrl + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: token } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: response.status, json: await response.json().catch(() => null) };
}

// Uma conta anônima, como a do app.
const email = `teste${Date.now()}@anon.cascapp.invalid`;
const password = 'senha-de-teste-1234';
assert.equal((await call('POST', '/api/collections/users/records', { email, password, passwordConfirm: password })).status, 200);
const auth = await call('POST', '/api/collections/users/auth-with-password', { identity: email, password });
const { token } = auth.json;
const owner = auth.json.record.id;

const review = (extra) => ({ owner, moves: GAME, side: 'white', hotseat: true, played_at: 1 + Math.floor(Math.random() * 1e9), ...extra });
const records = '/api/collections/chess_reviews/records';

for (const forged of [{ analysis: [{ best: 'e2e4' }] }, { engine: 'x' }, { status: 'done' }]) {
  const reply = await call('POST', records, review(forged), token);
  assert.equal(reply.status, 400, `o app não cria com ${Object.keys(forged)[0]}`);
}

const created = await call('POST', records, review({}), token);
assert.equal(created.status, 200, JSON.stringify(created.json));

const started = Date.now();
await run(config, { once: true });
const elapsed = Date.now() - started;

const done = (await call('GET', `${records}/${created.json.id}`, undefined, token)).json;
assert.equal(done.status, 'done');
assert.equal(done.engine, `sf19 nodes=${config.nodes}`);
assert.equal(done.analysis.length, 8, 'uma posição por lance, mais a inicial');
assert.equal(done.analysis[6].best, 'h5f7', 'depois de 3...Cf6 o melhor é Dxf7#');
assert.equal(done.analysis[6].mate, 1, 'mate em 1');
assert.deepEqual(done.analysis[6].wdl, [1000, 0, 0]);
for (const position of done.analysis) {
  assert.equal(position.wdl.reduce((a, b) => a + b, 0), 1000);
  assert.match(position.best, /^[a-h][1-8][a-h][1-8][qrbn]?$/);
}
console.log(`integração ok: ${done.analysis.length} posições em ${elapsed} ms`);
console.log(JSON.stringify(done.analysis.map((p) => [p.best, p.mate, p.wdl])));
