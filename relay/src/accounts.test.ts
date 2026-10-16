import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import { createVerifier, type Account, type TokenVerifier } from './accounts.js';
import { createRelay, type Relay } from './server.js';
import { Client } from './testing.js';

/** `fetch` de mentira: cada token tem uma resposta, e cada chamada é contada. */
function fakeFetch(answers: Record<string, () => Promise<Response>>): {
  fetchImpl: typeof fetch;
  calls: () => number;
} {
  let calls = 0;
  const fetchImpl = (async (_url: string | URL | Request, init?: RequestInit) => {
    calls += 1;
    const token = String((init?.headers as Record<string, string>).Authorization);
    const answer = answers[token];
    if (answer === undefined) return new Response('{}', { status: 401 });
    return answer();
  }) as typeof fetch;
  return { fetchImpl, calls: () => calls };
}

const ok = (name: string, extra: Record<string, unknown> = {}) => () =>
  Promise.resolve(
    new Response(JSON.stringify({ token: 'novo', record: { id: 'abcdefghij12345', name, ...extra } }), { status: 200 })
  );

describe('verificador de token', () => {
  it('token válido devolve o nome da conta, limpo', async () => {
    const { fetchImpl } = fakeFetch({ bom: ok('  Borzani\u0007 ') });
    const verify = createVerifier('http://pb', { fetchImpl });
    assert.equal((await verify('bom'))?.name, 'Borzani');
  });

  it('devolve o perfil público: id, foto e Elo', async () => {
    const { fetchImpl } = fakeFetch({
      bom: ok('Ana', { avatar: 'avatar_x1y2z3.webp', elo_chess: 1350, email: 'x@anon.cascapp.invalid' }),
    });
    const verify = createVerifier('http://pb', { fetchImpl });
    assert.deepEqual(await verify('bom'), {
      id: 'abcdefghij12345',
      name: 'Ana',
      avatar: 'avatar_x1y2z3.webp',
      elo: 1350,
    });
  });

  it('conta de antes do perfil vem sem foto e com Elo 0; campo estranho não passa', async () => {
    const { fetchImpl } = fakeFetch({
      velha: ok('Velha'),
      estranha: ok('Estranha', { avatar: '../../etc/passwd', elo_chess: 'muito' }),
      sem_id: () => Promise.resolve(new Response(JSON.stringify({ record: { name: 'X' } }), { status: 200 })),
    });
    const verify = createVerifier('http://pb', { fetchImpl });
    assert.deepEqual(await verify('velha'), { id: 'abcdefghij12345', name: 'Velha', avatar: '', elo: 0 });
    const odd = await verify('estranha');
    assert.equal(odd?.avatar, '', 'caminho no nome do arquivo não passa');
    assert.equal(odd?.elo, 0);
    assert.equal(await verify('sem_id'), null, 'sem id não é conta');
  });

  it('token recusado, sem nome ou com erro de rede é null', async () => {
    const { fetchImpl } = fakeFetch({
      vazio: ok(''),
      quebrado: () => Promise.reject(new Error('rede')),
    });
    const verify = createVerifier('http://pb', { fetchImpl });
    assert.equal(await verify('estranho'), null);
    assert.equal(await verify('vazio'), null);
    assert.equal(await verify('quebrado'), null);
  });

  it('PocketBase lento é null dentro do tempo', async () => {
    const slow = (async (_url: string | URL | Request, init?: RequestInit) =>
      new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () => reject(new Error('abort')));
      })) as typeof fetch;
    const verify = createVerifier('http://pb', { fetchImpl: slow, timeoutMs: 50 });
    const started = Date.now();
    assert.equal(await verify('qualquer'), null);
    assert.ok(Date.now() - started < 1_000);
  });

  it('o positivo vai para o cache; a falha não', async () => {
    let up = false;
    const { fetchImpl, calls } = fakeFetch({
      bom: ok('Ana'),
      volta: () => (up ? ok('Bia')() : Promise.reject(new Error('fora'))),
    });
    const verify = createVerifier('http://pb', { fetchImpl });
    await verify('bom');
    await verify('bom');
    assert.equal(calls(), 1, 'a segunda pergunta sai do cache');
    assert.equal(await verify('volta'), null);
    up = true;
    assert.equal((await verify('volta'))?.name, 'Bia', 'a falha passageira não ficou guardada');
  });
});

// --- ponta a ponta: o relay confirmando nomes na sala ------------------------

let relay: Relay;
let url: string;
let release: () => void = () => {};

const ANA: Account = { id: 'anaanaanaana123', name: 'Ana', avatar: 'avatar_x1y2z3.webp', elo: 1350 };
const LENTO: Account = { id: 'lentolentolent0', name: 'Lento', avatar: '', elo: 1200 };

/** `lento` só responde quando o teste chamar `release()`. */
const verifyToken: TokenVerifier = async (token) => {
  if (token === 'ana') return ANA;
  if (token === 'lento') {
    await new Promise<void>((resolve) => {
      release = resolve;
    });
    return LENTO;
  }
  return null;
};

before(async () => {
  relay = createRelay({ helloTimeoutMs: 500, roomGraceMs: 60_000, verifyToken });
  const port = await relay.listen(0, '127.0.0.1');
  url = `ws://127.0.0.1:${port}/ws`;
});

after(async () => {
  await relay.close();
});

describe('nome confirmado na sala', () => {
  it('quem tem conta tem o nome confirmado para todos, inclusive quem chega depois', async () => {
    const host = await Client.open(url);
    host.send({ t: 'host', room: 'CONTA1', game: 'chess', token: 'ana' });
    assert.equal((await host.next()).t, 'joined');
    assert.deepEqual(await host.next(), { t: 'identity', seat: 0, name: 'Ana', user: ANA.id, avatar: ANA.avatar, elo: ANA.elo });

    const guest = await Client.open(url);
    guest.send({ t: 'join', room: 'CONTA1' });
    assert.equal((await guest.next()).t, 'joined');
    assert.deepEqual(await guest.next(), { t: 'identity', seat: 0, name: 'Ana', user: ANA.id, avatar: ANA.avatar, elo: ANA.elo });
    assert.deepEqual(await host.next(), { t: 'peer', seat: 1 });
    await guest.quiet();

    const watcher = await Client.open(url);
    watcher.send({ t: 'watch', room: 'CONTA1' });
    assert.equal((await watcher.next()).t, 'watching');
    assert.deepEqual(await watcher.next(), { t: 'identity', seat: 0, name: 'Ana', user: ANA.id, avatar: ANA.avatar, elo: ANA.elo });
    host.close();
    guest.close();
    watcher.close();
  });

  it('token recusado não confirma nada, e a sala segue igual', async () => {
    const host = await Client.open(url);
    host.send({ t: 'host', room: 'CONTA2', game: 'chess', token: 'forjado' });
    assert.equal((await host.next()).t, 'joined');
    await host.quiet();
    host.close();
  });

  it('a conferência não atrasa a entrada, e a confirmação chega depois', async () => {
    const host = await Client.open(url);
    host.send({ t: 'host', room: 'CONTA3', game: 'chess' });
    assert.equal((await host.next()).t, 'joined');
    const guest = await Client.open(url);
    guest.send({ t: 'join', room: 'CONTA3', token: 'lento' });
    assert.equal((await guest.next()).t, 'joined', 'entrou sem esperar o PocketBase');
    assert.deepEqual(await host.next(), { t: 'peer', seat: 1 });
    release();
    assert.deepEqual(await host.next(), { t: 'identity', seat: 1, name: 'Lento', user: LENTO.id, avatar: '', elo: 1200 });
    assert.deepEqual(await guest.next(), { t: 'identity', seat: 1, name: 'Lento', user: LENTO.id, avatar: '', elo: 1200 });
    host.close();
    guest.close();
  });

  it('confirmação que chega depois de o jogador sair é descartada', async () => {
    const host = await Client.open(url);
    host.send({ t: 'host', room: 'CONTA4', game: 'chess' });
    assert.equal((await host.next()).t, 'joined');
    const guest = await Client.open(url);
    guest.send({ t: 'join', room: 'CONTA4', token: 'lento' });
    assert.equal((await guest.next()).t, 'joined');
    assert.deepEqual(await host.next(), { t: 'peer', seat: 1 });
    guest.close();
    assert.deepEqual(await host.next(), { t: 'peer_left', seat: 1 });
    release();
    await host.quiet();
    host.close();
  });
});
