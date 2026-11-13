// node --test pocketbase/worker/worker.test.mjs
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { analyse, Engine, handle, parseMoves, positionCommand, readInfo } from './worker.mjs';

const FAKE = fileURLToPath(new URL('./fake-stockfish.mjs', import.meta.url));
const cfg = { nodes: 1000, movetimeMs: 500, threads: 1, hashMb: 16, maxPlies: 300 };

function fake(extraEnv = {}) {
  const log = join(mkdtempSync(join(tmpdir(), 'fake-sf-')), 'log');
  Object.assign(process.env, { FAKE_LOG: log, FAKE_DIE_AT: '' }, extraEnv);
  const engine = new Engine(process.execPath, [FAKE]);
  const sent = () => (existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n').map((l) => JSON.parse(l)) : []);
  return { engine, sent };
}

function memoryDb() {
  const saved = [];
  return { saved, save: async (id, fields) => { saved.push({ id, ...fields }); } };
}

test('lê nota, WDL e PV da linha principal', () => {
  const seen = readInfo('info depth 18 multipv 1 score cp 31 wdl 512 400 88 nodes 9 pv e2e4 e7e5 g1f3', { wdl: [0, 1000, 0], mate: 0, pv: '' });
  assert.deepEqual(seen, { wdl: [512, 400, 88], mate: 0, pv: 'e2e4 e7e5 g1f3' });
});

test('mate sem WDL, posição já em mate e linhas que não contam', () => {
  const start = { wdl: [0, 1000, 0], mate: 0, pv: '' };
  assert.deepEqual(readInfo('info depth 5 score mate 3 pv d1h5', start).wdl, [1000, 0, 0]);
  assert.deepEqual(readInfo('info depth 0 score mate 0', start), { wdl: [0, 0, 1000], mate: 0, pv: '' });
  assert.equal(readInfo('info depth 9 multipv 2 score cp -50 pv a2a3', start), start);
  assert.equal(readInfo('info depth 1 currmove e2e4 currmovenumber 1', start), start);
  assert.equal(readInfo('bestmove e2e4', start), start);
});

test('lances: aceita UCI, recusa injeção e corta no teto', () => {
  assert.deepEqual(parseMoves('e2e4 e7e5 a7a8q', 300), ['e2e4', 'e7e5', 'a7a8q']);
  for (const bad of ['', 'e2e4\nquit', 'e2e4 \nsetoption name Debug Log File value /x', 'e2e4  e7e5', 'e2e9', null]) {
    assert.throws(() => parseMoves(bad, 300), /lances inválidos/, JSON.stringify(bad));
  }
  assert.deepEqual(parseMoves('e2e4 e7e5 g1f3', 2), ['e2e4', 'e7e5']);
});

test('posição pela lista de lances', () => {
  assert.equal(positionCommand(['e2e4', 'e7e5'], 0), 'position startpos');
  assert.equal(positionCommand(['e2e4', 'e7e5'], 1), 'position startpos moves e2e4');
});

test('uma posição por lance, mais a inicial, por nós e com teto de tempo', async () => {
  const { engine, sent } = fake();
  await engine.start(cfg);
  const out = await analyse(engine, 'e2e4 e7e5', cfg);
  engine.quit();
  assert.equal(out.length, 3);
  assert.deepEqual(out[0], { wdl: [500, 400, 100], mate: 0, best: 'e2e4', pv: 'e2e4 e7e5' });
  const commands = sent();
  assert.ok(commands.includes('setoption name UCI_ShowWDL value true'));
  assert.deepEqual(commands.filter((c) => c.startsWith('position')), [
    'position startpos', 'position startpos moves e2e4', 'position startpos moves e2e4 e7e5',
  ]);
  assert.ok(commands.filter((c) => c.startsWith('go')).every((c) => c === 'go nodes 1000 movetime 500'));
});

test('lances com quebra de linha viram failed sem chegar ao motor', async () => {
  const { engine, sent } = fake();
  await engine.start(cfg);
  const db = memoryDb();
  const next = await handle({ id: 'r1', moves: 'e2e4\nsetoption name Debug Log File value /tmp/x' }, engine, db, cfg, () => assert.fail());
  assert.equal(next, engine);
  next.quit();
  assert.deepEqual(db.saved, [{ id: 'r1', status: 'failed', engine: 'sf19 nodes=1000' }]);
  assert.ok(!sent().some((c) => c.startsWith('position') || c.includes('Debug')));
});

test('motor que morre no meio: failed, e a próxima usa um motor novo', async () => {
  const { engine } = fake({ FAKE_DIE_AT: '2' });
  await engine.start(cfg);
  const db = memoryDb();
  const fresh = () => { process.env.FAKE_DIE_AT = ''; return new Engine(process.execPath, [FAKE]); };
  const next = await handle({ id: 'r1', moves: 'e2e4 e7e5' }, engine, db, cfg, fresh);
  assert.notEqual(next, engine);
  assert.equal(db.saved[0].status, 'failed');
  await handle({ id: 'r2', moves: 'e2e4' }, next, db, cfg, () => assert.fail());
  next.quit();
  assert.equal(db.saved[1].status, 'done');
  assert.equal(db.saved[1].analysis.length, 2);
});
