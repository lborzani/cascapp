// node --test pocketbase/worker/search.test.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createLimiter, createSearch, createVerifier, fenProblem, positionFor, serve } from './search.mjs';

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const cfg = { nodes: 1000, movetimeMs: 500, maxPlies: 600, maxPending: 2, cacheSize: 2 };

/** Motor de mentira: anota os comandos e responde na hora (ou quando mandarem). */
function fakeEngine({ die = false, hold = null } = {}) {
  const engine = {
    sent: [], dead: null, quits: 0,
    async search(command) {
      engine.sent.push(command);
      if (hold) await hold;
      if (die) {
        engine.dead = new Error('motor saiu');
        throw engine.dead;
      }
      return { wdl: [500, 400, 100], mate: 0, best: 'e2e4', pv: 'e2e4 e7e5' };
    },
    start: async () => {},
    quit() { engine.quits += 1; },
  };
  return engine;
}

const okVerify = async (token) => (token === 'bom' ? 'conta1' : null);

test('FEN: aceita a inicial e recusa o que derrubaria o motor', () => {
  assert.equal(fenProblem(START), null);
  assert.equal(fenProblem('8/5pk1/6p1/8/3R4/6P1/5PK1/3r4 w - - 0 40'), null);
  const bad = {
    'quebra de linha': `${START}\nquit`,
    'comando colado': `${START} moves e2e4`,
    'fileira curta': 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPP/RNBQKBNR w KQkq - 0 1',
    'sem rei preto': 'rnbq1bnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQ - 0 1',
    'dois reis brancos': 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBKKBNR w - - 0 1',
    'peão na oitava': 'rnbqkbnP/pppppppp/8/8/8/8/PPPPPPP1/RNBQKBNR w - - 0 1',
    'roque vazio': 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w  - 0 1',
    'não é texto': 42,
  };
  for (const [label, fen] of Object.entries(bad)) assert.notEqual(fenProblem(fen), null, label);
});

test('posição: FEN ou lances, nunca os dois, e lances validados', () => {
  assert.deepEqual(positionFor({ fen: START }, 600).command, `position fen ${START}`);
  assert.deepEqual(positionFor({ moves: 'e2e4 e7e5' }, 600).command, 'position startpos moves e2e4 e7e5');
  assert.deepEqual(positionFor({ moves: '' }, 600).command, 'position startpos');
  assert.throws(() => positionFor({}, 600), /fen.*moves/);
  assert.throws(() => positionFor({ fen: START, moves: 'e2e4' }, 600), /fen.*moves/);
  assert.throws(() => positionFor({ moves: 'e2e4\nquit' }, 600), /inválidos/);
  assert.throws(() => positionFor({ moves: 'e2e4 e7e5 g1f3' }, 2), /longa/);
});

test('limite por conta e por minuto', () => {
  const limit = createLimiter(2);
  assert.ok(limit('a', 0) && limit('a', 1));
  assert.ok(!limit('a', 2), 'terceiro no mesmo minuto');
  assert.ok(limit('b', 3), 'outra conta tem o dela');
  assert.ok(limit('a', 60000), 'minuto novo zera');
});

test('token: confere no PocketBase e guarda por um tempo', async () => {
  let calls = 0;
  const fetchImpl = async (url, options) => {
    calls += 1;
    assert.match(url, /auth-refresh$/);
    const ok = options.headers.Authorization === 'bom';
    return { ok, json: async () => ({ record: { id: 'conta1' } }) };
  };
  const verify = createVerifier('http://pb', { ttlMs: 1000, fetchImpl });
  assert.equal(await verify('bom', 0), 'conta1');
  assert.equal(await verify('bom', 500), 'conta1');
  assert.equal(calls, 1, 'a segunda vem do cache');
  assert.equal(await verify('ruim', 0), null);
  assert.equal(await verify('', 0), null);
  assert.equal(await verify('bom', 2000), 'conta1');
  assert.equal(calls, 3, 'venceu, confere de novo');
  const down = createVerifier('http://pb', { fetchImpl: async () => { throw new Error('fora'); } });
  assert.equal(await down('bom'), null);
});

test('pedido: 401, 429, 400 sem chegar ao motor, 200 e cache', async () => {
  const engine = fakeEngine();
  // Conta todo pedido de quem tem conta, até o 400 e o do cache: 3 por minuto.
  const handle = createSearch({ engine, newEngine: () => assert.fail(), verify: okVerify, limit: createLimiter(3), cfg });
  assert.equal((await handle({ token: 'ruim', body: { fen: START } })).status, 401);
  assert.equal((await handle({ token: 'bom', body: { fen: `${START}\nquit` } })).status, 400);
  const first = await handle({ token: 'bom', body: { fen: START } });
  assert.deepEqual(first, { status: 200, body: { wdl: [500, 400, 100], mate: 0, best: 'e2e4', pv: 'e2e4 e7e5' } });
  assert.equal((await handle({ token: 'bom', body: { fen: START } })).status, 200);
  assert.deepEqual(engine.sent, [`position fen ${START}`], 'a repetida veio do cache, e a ruim nunca chegou');
  assert.equal((await handle({ token: 'bom', body: { moves: '' } })).status, 429, 'quarto pedido da conta no minuto');
});

test('fila cheia responde 503 sem esperar', async () => {
  let release;
  const hold = new Promise((r) => { release = r; });
  const engine = fakeEngine({ hold });
  const handle = createSearch({ engine, newEngine: () => assert.fail(), verify: okVerify, limit: () => true, cfg });
  const a = handle({ token: 'bom', body: { moves: 'e2e4' } });
  const b = handle({ token: 'bom', body: { moves: 'd2d4' } });
  assert.equal((await handle({ token: 'bom', body: { moves: 'c2c4' } })).status, 503);
  release();
  assert.deepEqual([(await a).status, (await b).status], [200, 200]);
  assert.deepEqual(engine.sent, ['position startpos moves e2e4', 'position startpos moves d2d4'], 'um de cada vez, na ordem');
});

test('motor que morre: 500 nesse pedido, e o próximo usa um motor novo', async () => {
  const dying = fakeEngine({ die: true });
  const fresh = fakeEngine();
  const handle = createSearch({ engine: dying, newEngine: () => fresh, verify: okVerify, limit: () => true, cfg });
  assert.equal((await handle({ token: 'bom', body: { moves: 'e2e4' } })).status, 500);
  assert.equal(dying.quits, 1);
  assert.equal((await handle({ token: 'bom', body: { moves: 'e2e4' } })).status, 200);
  assert.deepEqual(fresh.sent, ['position startpos moves e2e4']);
});

test('HTTP: só POST /search, JSON, e o token do cabeçalho', async () => {
  let got = null;
  const server = serve(async (request) => { got = request; return { status: 200, body: { ok: true } }; }, 0);
  await new Promise((r) => server.once('listening', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.equal((await fetch(`${base}/search`)).status, 404);
    assert.equal((await fetch(`${base}/outra`, { method: 'POST', body: '{}' })).status, 404);
    assert.equal((await fetch(`${base}/search`, { method: 'POST', body: 'não é json' })).status, 400);
    assert.equal((await fetch(`${base}/search`, { method: 'POST', body: 'x'.repeat(9000) })).status, 413);
    const ok = await fetch(`${base}/search`, { method: 'POST', headers: { Authorization: 'Bearer bom' }, body: '{"moves":""}' });
    assert.equal(ok.status, 200);
    assert.deepEqual(got, { token: 'bom', body: { moves: '' } });
  } finally {
    server.close();
  }
});
