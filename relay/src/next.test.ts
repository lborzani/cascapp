import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, it } from 'node:test';

import type { Account, TokenVerifier } from './accounts.js';
import type { RatedGame } from './ratings.js';
import { createRelay, type Relay } from './server.js';
import { Client } from './testing.js';

/**
 * Fila de quem joga a próxima, ponta a ponta: o espectador pede, o jogador
 * cede, e os dois trocam de papel sem o assento ficar livre.
 */

const ANA: Account = { id: 'anaanaanaana123', name: 'Ana', avatar: '', elo: 1200 };
const BIA: Account = { id: 'biabiabiabia123', name: 'Bia', avatar: '', elo: 1200 };
const CAIO: Account = { id: 'caiocaiocaio123', name: 'Caio', avatar: '', elo: 1300 };
const verifyToken: TokenVerifier = async (token) =>
  token === 'ana' ? ANA : token === 'bia' ? BIA : token === 'caio' ? CAIO : null;

let relay: Relay;
let url: string;
let calls: RatedGame[] = [];

before(async () => {
  relay = createRelay({
    helloTimeoutMs: 500,
    roomGraceMs: 60_000,
    abandonMs: 150,
    verifyToken,
    reportResult: async (game) => {
      calls.push(game);
      return { white: { elo: 1220, delta: 20 }, black: { elo: 1180, delta: -20 } };
    },
  });
  url = `ws://127.0.0.1:${await relay.listen(0, '127.0.0.1')}/ws`;
});

after(async () => {
  await relay.close();
});

beforeEach(() => {
  calls = [];
});

/** Mesa cheia com contas confirmadas e um espectador, já com tudo lido. */
async function watched(room: string): Promise<{ host: Client; guest: Client; viewer: Client }> {
  const host = await Client.open(url);
  host.send({ t: 'host', room, game: 'chess', token: 'ana' });
  await host.nextOf('identity');
  const guest = await Client.open(url);
  guest.send({ t: 'join', room, token: 'bia' });
  await host.nextOf('identity');
  await guest.nextOf('identity');
  const viewer = await Client.open(url);
  viewer.send({ t: 'watch', room });
  await viewer.nextOf('watching');
  await viewer.nextOf('identity');
  await viewer.nextOf('identity');
  await host.nextOf('watchers');
  await guest.nextOf('watchers');
  return { host, guest, viewer };
}

const MOVES = 'b'.repeat(64);
const result = (winner: number) => ({ t: 'result', winner, white: 0, plies: 40, moves: MOVES });

describe('fila de quem joga a próxima', () => {
  it('todos veem a fila; jogador não entra nela', async () => {
    const { host, guest, viewer } = await watched('NEXT10');

    viewer.send({ t: 'queue', on: true, name: 'Caio', token: 'caio' });
    assert.deepEqual(await viewer.nextOf('queue'), { t: 'queue', names: ['Caio'], you: 0 });
    assert.deepEqual(await host.nextOf('queue'), { t: 'queue', names: ['Caio'], you: -1 });
    assert.deepEqual(await guest.nextOf('queue'), { t: 'queue', names: ['Caio'], you: -1 });

    host.send({ t: 'queue', on: true, name: 'Ana' });
    await host.quiet();

    // Quem chega depois já vê a fila.
    const late = await Client.open(url);
    late.send({ t: 'watch', room: 'NEXT10' });
    await late.nextOf('watching');
    assert.deepEqual(await late.nextOf('queue'), { t: 'queue', names: ['Caio'], you: -1 });

    // Sair de assistir tira da fila, e todos ficam sabendo.
    viewer.close();
    assert.deepEqual(await host.nextOf('queue'), { t: 'queue', names: [], you: -1 });
    assert.deepEqual(await late.nextOf('queue'), { t: 'queue', names: [], you: -1 });

    for (const client of [host, guest, late]) client.close();
  });

  it('quem cede vira espectador e o primeiro da fila senta, sem assento livre', async () => {
    const { host, guest, viewer } = await watched('NEXT11');
    viewer.send({ t: 'queue', on: true, name: 'Caio', token: 'caio' });
    await viewer.nextOf('queue');
    await host.nextOf('queue');
    await guest.nextOf('queue');

    // Espectador não cede nada.
    viewer.send({ t: 'yield' });
    await host.quiet();

    guest.send({ t: 'yield' });
    const seated = await viewer.nextOf('swap');
    assert.equal(seated.seat, 1);
    assert.equal(seated.name, 'Caio');
    assert.equal(typeof seated.key, 'string');
    assert.ok((seated.key ?? '').length > 0, 'quem sentou recebe a chave do assento');
    assert.deepEqual(await host.next(), { t: 'swap', seat: 1, name: 'Caio', watchers: 1 }, 'sem peer_left antes');
    assert.deepEqual(await guest.next(), { t: 'swap', seat: 1, name: 'Caio', watchers: 1 });

    // A fila esvaziou para todos; a conta de quem sentou é conferida de novo.
    assert.deepEqual(await host.nextOf('queue'), { t: 'queue', names: [], you: -1 });
    const identity = await host.nextOf('identity');
    assert.deepEqual([identity.seat, identity.name], [1, 'Caio']);

    // O novo jogador fala com o assento dele; quem cedeu não fala mais.
    viewer.send({ t: 'msg', d: { t: 'move', n: 0 } });
    assert.deepEqual(await host.nextOf('msg'), { t: 'msg', d: { t: 'move', n: 0 }, from: 1 });
    assert.deepEqual(await guest.nextOf('msg'), { t: 'msg', d: { t: 'move', n: 0 }, from: 1 });
    guest.send({ t: 'msg', d: { t: 'bye' } });
    await host.quiet();

    // Ceder de novo sem fila: nada acontece.
    viewer.send({ t: 'yield' });
    await host.quiet();

    // A chave nova traz quem sentou de volta ao mesmo assento depois de uma queda.
    viewer.close();
    assert.deepEqual(await host.nextOf('peer_left'), { t: 'peer_left', seat: 1 });
    const back = await Client.open(url);
    back.send({ t: 'join', room: 'NEXT11', key: seated.key, token: 'caio' });
    const joined = await back.nextOf('joined');
    assert.equal(joined.seat, 1);

    for (const client of [host, guest, back]) client.close();
  });

  it('relato pendente de quem cedeu não grava no nome de quem sentou', async () => {
    const { host, guest, viewer } = await watched('NEXT12');
    viewer.send({ t: 'queue', on: true, name: 'Caio', token: 'caio' });
    await guest.nextOf('queue');

    // Só quem perdeu contou antes de ceder: o relato fica esperando o outro.
    guest.send(result(0));
    guest.send({ t: 'yield' });
    await host.nextOf('swap');
    await host.nextOf('identity');
    host.send(result(0));
    await new Promise((resolve) => setTimeout(resolve, 250));
    assert.equal(calls.length, 0, 'a partida não vira Ana contra Caio');

    for (const client of [host, guest, viewer]) client.close();
  });
});
