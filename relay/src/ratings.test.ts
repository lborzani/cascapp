import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import type { Account, TokenVerifier } from './accounts.js';
import { createReporter, decide, parseReport, type RatedGame, type Report } from './ratings.js';
import { createRelay, type Relay } from './server.js';
import { Client } from './testing.js';

const MOVES = 'a'.repeat(64);
const report = (winner: number, overrides: Partial<Report> = {}): Report =>
  ({ winner, white: 0, plies: 40, moves: MOVES, ...overrides }) as Report;

describe('decisão do árbitro', () => {
  it('os dois contam o mesmo: conta', () => {
    const verdict = decide(new Map([[0, report(0)], [1, report(0)]]), new Map(), 0, 1000);
    assert.equal(verdict.kind, 'rate');
  });

  it('relatos diferentes: não conta', () => {
    assert.equal(decide(new Map([[0, report(0)], [1, report(1)]]), new Map(), 0, 1000).kind, 'none');
    assert.equal(decide(new Map([[0, report(0)], [1, report(0, { plies: 41 })]]), new Map(), 0, 1000).kind, 'none');
  });

  it('só um contou com o outro presente: espera o outro', () => {
    assert.equal(decide(new Map([[0, report(0)]]), new Map(), 0, 1000).kind, 'none');
  });

  it('o outro saiu: vale sozinho depois da espera do abandono', () => {
    const reports = new Map([[0, report(0)]]);
    assert.deepEqual(decide(reports, new Map([[1, 100]]), 400, 1000), { kind: 'wait', ms: 700 });
    assert.equal(decide(reports, new Map([[1, 100]]), 1100, 1000).kind, 'rate');
  });

  it('o relato tem forma conhecida ou não entra', () => {
    assert.deepEqual(parseReport({ winner: 1, white: 0, plies: 12, moves: MOVES }), report(1, { plies: 12 }));
    assert.equal(parseReport({ winner: 2, white: 0, plies: 12, moves: MOVES }), null);
    assert.equal(parseReport({ winner: 0, white: 0, plies: -1, moves: MOVES }), null);
    assert.equal(parseReport({ winner: 0, white: 0, plies: 12, moves: 'curto' }), null);
  });
});

describe('gravar no PocketBase', () => {
  it('manda o segredo e lê o Elo novo', async () => {
    let seen: RequestInit | undefined;
    const fetchImpl = (async (_url: string | URL | Request, init?: RequestInit) => {
      seen = init;
      return new Response(JSON.stringify({ white: { elo: 1220, delta: 20 }, black: { elo: 1180, delta: -20 } }));
    }) as typeof fetch;
    const reporter = createReporter('http://pb/', 'segredo', { fetchImpl });
    const game: RatedGame = { key: 'k', white: 'a', black: 'b', result: 'white', plies: 40 };
    assert.deepEqual(await reporter(game), { white: { elo: 1220, delta: 20 }, black: { elo: 1180, delta: -20 } });
    assert.equal((seen?.headers as Record<string, string>)['X-Cascapp-Relay'], 'segredo');
  });

  it('recusa ou rede fora é null', async () => {
    const refused = createReporter('http://pb', 's', {
      fetchImpl: (async () => new Response('{}', { status: 403 })) as typeof fetch,
    });
    const down = createReporter('http://pb', 's', {
      fetchImpl: (async () => Promise.reject(new Error('fora'))) as typeof fetch,
    });
    const game: RatedGame = { key: 'k', white: 'a', black: 'b', result: 'draw', plies: 40 };
    assert.equal(await refused(game), null);
    assert.equal(await down(game), null);
  });
});

// --- ponta a ponta -------------------------------------------------------------

const ANA: Account = { id: 'anaanaanaana123', name: 'Ana', avatar: '', elo: 1200 };
const BIA: Account = { id: 'biabiabiabia123', name: 'Bia', avatar: '', elo: 1200 };
const verifyToken: TokenVerifier = async (token) =>
  token === 'devagar'
    ? new Promise((resolve) => setTimeout(() => resolve(BIA), 120))
    : token === 'ana' ? ANA : token === 'bia' ? BIA : token === 'ana2' ? { ...ANA } : null;

type Answer = { white: { elo: number; delta: number }; black: { elo: number; delta: number } } | null;

let relay: Relay;
let url: string;
let calls: RatedGame[] = [];
let answer: Answer = null;

before(async () => {
  relay = createRelay({
    helloTimeoutMs: 500,
    roomGraceMs: 60_000,
    abandonMs: 150,
    verifyToken,
    reportResult: async (game) => {
      calls.push(game);
      return answer;
    },
  });
  url = `ws://127.0.0.1:${await relay.listen(0, '127.0.0.1')}/ws`;
});

after(async () => {
  await relay.close();
});

beforeEach(() => {
  calls = [];
  answer = { white: { elo: 1220, delta: 20 }, black: { elo: 1180, delta: -20 } };
});

/** Uma mesa com os dois sentados e as contas já confirmadas. */
async function table(room: string, guestToken = 'bia', game = 'chess'): Promise<[Client, Client]> {
  const host = await Client.open(url);
  host.send({ t: 'host', room, game, token: 'ana' });
  await host.nextOf('identity');
  const guest = await Client.open(url);
  guest.send({ t: 'join', room, token: guestToken });
  if (guestToken !== '') {
    await host.nextOf('identity');
    await guest.nextOf('identity');
  } else {
    await host.nextOf('peer');
  }
  return [host, guest];
}

const pause = (ms = 60) => new Promise((resolve) => setTimeout(resolve, ms));
const result = (winner: number, white = 0, plies = 40, moves = MOVES) => ({ t: 'result', winner, white, plies, moves });

describe('o relay arbitra o Elo', () => {
  it('os dois contam a vitória das brancas: grava e avisa os dois', async () => {
    const [host, guest] = await table('ELO001');
    host.send(result(0));
    guest.send(result(0));
    const rated = await host.nextOf('rated');
    assert.deepEqual(rated.ratings, [
      { seat: 0, elo: 1220, delta: 20 },
      { seat: 1, elo: 1180, delta: -20 },
    ]);
    assert.deepEqual((await guest.nextOf('rated')).ratings, rated.ratings);
    assert.equal(calls.length, 1);
    assert.deepEqual({ ...calls[0], key: '' }, { key: '', white: ANA.id, black: BIA.id, result: 'white', plies: 40 });

    // Reenviado por uma reconexão: não conta de novo.
    host.send(result(0));
    guest.send(result(0));
    await pause();
    assert.equal(calls.length, 1, 'a mesma partida conta uma vez');
    host.close();
    guest.close();
  });

  it('cores trocadas na revanche: quem é brancas vem do relato', async () => {
    const [host, guest] = await table('ELO002');
    host.send(result(0, 1, 30, 'b'.repeat(64)));
    guest.send(result(0, 1, 30, 'b'.repeat(64)));
    await host.nextOf('rated');
    assert.equal(calls[0]?.white, BIA.id);
    assert.equal(calls[0]?.result, 'black', 'o assento 0 venceu de pretas');
    host.close();
    guest.close();
  });

  it('relato que chega antes da conta confirmada espera por ela', async () => {
    const host = await Client.open(url);
    host.send({ t: 'host', room: 'ELO012', game: 'chess', token: 'ana' });
    await host.nextOf('identity');
    const guest = await Client.open(url);
    guest.send({ t: 'join', room: 'ELO012', token: 'devagar' });
    await guest.nextOf('joined');
    host.send(result(0));
    guest.send(result(0));
    await host.nextOf('rated');
    assert.equal(calls.length, 1);
    host.close();
    guest.close();
  });

  it('relatos que não batem não contam', async () => {
    const [host, guest] = await table('ELO003');
    host.send(result(0));
    guest.send(result(1));
    await host.quiet();
    assert.equal(calls.length, 0);
    host.close();
    guest.close();
  });

  it('quem perde e fecha o app perde do mesmo jeito', async () => {
    const [host, guest] = await table('ELO004');
    guest.close();
    await host.nextOf('peer_left');
    host.send(result(0, 0, 22));
    await pause(80);
    assert.equal(calls.length, 0, 'antes da espera do abandono, nada');
    await host.nextOf('rated');
    assert.equal(calls[0]?.result, 'white');
    host.close();
  });

  it('o outro volta dentro da espera: o relato sozinho não vale mais', async () => {
    const [host, guest] = await table('ELO005');
    guest.close();
    await host.nextOf('peer_left');
    host.send(result(0, 0, 22));
    const back = await Client.open(url);
    back.send({ t: 'join', room: 'ELO005', token: 'bia' });
    await back.nextOf('joined');
    await pause(250);
    assert.equal(calls.length, 0);
    host.close();
    back.close();
  });

  it('partida curta, sem conta, mesma conta ou outro jogo: não conta', async () => {
    const tables = [
      [await table('ELO006'), 2],
      [await table('ELO007', ''), 40],
      [await table('ELO008', 'ana2'), 40],
      [await table('ELO009', 'bia', 'checkers'), 40],
    ] as const;
    for (const [[host, guest], plies] of tables) {
      host.send(result(0, 0, plies));
      guest.send(result(0, 0, plies));
    }
    await pause();
    assert.equal(calls.length, 0);
    for (const [[host, guest]] of tables) {
      host.close();
      guest.close();
    }
  });

  it('PocketBase fora: a partida segue, ninguém recebe rated', async () => {
    answer = null;
    const [host, guest] = await table('ELO010');
    host.send(result(-1, 0, 80));
    guest.send(result(-1, 0, 80));
    await host.quiet();
    assert.equal(calls[0]?.result, 'draw');
    host.close();
    guest.close();
  });

  it('quem assiste não conta resultado', async () => {
    const [host, guest] = await table('ELO011');
    const watcher = await Client.open(url);
    watcher.send({ t: 'watch', room: 'ELO011' });
    await watcher.nextOf('watching');
    watcher.send(result(0));
    host.send(result(0));
    await pause();
    assert.equal(calls.length, 0, 'o relato do espectador não faz par');
    host.close();
    guest.close();
    watcher.close();
  });
});
