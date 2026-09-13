import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { WebSocket } from 'ws';

import type { ServerMessage } from './protocol.js';
import { createRelay, type Relay } from './server.js';

/**
 * Ponta a ponta com sockets de verdade em porta efêmera. O que interessa aqui
 * não é o repasse (trivial), é o que acontece quando um lado cai: esse é o
 * caminho que a rede móvel exercita o tempo todo e que nenhum teste unitário
 * do registro cobre sozinho.
 */

let relay: Relay;
let url: string;

before(async () => {
  relay = createRelay({ helloTimeoutMs: 500, roomGraceMs: 60_000 });
  const port = await relay.listen(0, '127.0.0.1');
  url = `ws://127.0.0.1:${port}/ws`;
});

after(async () => {
  await relay.close();
});

/** Socket com uma fila de mensagens, para o teste poder esperar por cada uma. */
class Client {
  private readonly inbox: ServerMessage[] = [];
  private waiting: ((message: ServerMessage) => void) | null = null;

  private constructor(private readonly socket: WebSocket) {
    socket.on('message', (raw) => {
      const message = JSON.parse(raw.toString()) as ServerMessage;
      if (this.waiting !== null) {
        const resolve = this.waiting;
        this.waiting = null;
        resolve(message);
      } else {
        this.inbox.push(message);
      }
    });
  }

  static open(target: string): Promise<Client> {
    return new Promise((resolve, reject) => {
      const socket = new WebSocket(target);
      socket.once('open', () => resolve(new Client(socket)));
      socket.once('error', reject);
    });
  }

  send(payload: unknown): void {
    this.socket.send(JSON.stringify(payload));
  }

  next(timeoutMs = 2_000): Promise<ServerMessage> {
    const queued = this.inbox.shift();
    if (queued !== undefined) return Promise.resolve(queued);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('nenhuma mensagem chegou')), timeoutMs);
      this.waiting = (message) => {
        clearTimeout(timer);
        resolve(message);
      };
    });
  }

  /** O `joined`, com a chave do assento — que é o que a reconexão precisa. */
  async joined(): Promise<{ seat: number; seats: number; present: number[]; key: string }> {
    const message = await this.next();
    assert.equal(message.t, 'joined');
    if (message.t !== 'joined') throw new Error('inalcançável');
    return { seat: message.seat, seats: message.seats, present: message.present, key: message.key };
  }

  closed(): Promise<void> {
    if (this.socket.readyState === WebSocket.CLOSED) return Promise.resolve();
    return new Promise((resolve) => this.socket.once('close', () => resolve()));
  }

  /** Corta sem handshake de fechamento — é o que a rede faz de verdade. */
  kill(): void {
    this.socket.terminate();
  }

  close(): void {
    this.socket.close();
  }
}

async function pair(code: string): Promise<{ host: Client; guest: Client }> {
  const host = await Client.open(url);
  host.send({ t: 'host', room: code, game: 'chess' });
  const opened = await host.joined();
  assert.equal(opened.seat, 0);
  assert.equal(opened.seats, 2);
  assert.deepEqual(opened.present, [0]);

  const guest = await Client.open(url);
  guest.send({ t: 'join', room: code });
  const seated = await guest.joined();
  assert.equal(seated.seat, 1);
  assert.deepEqual(seated.present, [0, 1]);
  assert.deepEqual(await host.next(), { t: 'peer', seat: 1 });

  return { host, guest };
}

/**
 * Sala de quatro, cheia. Devolve os clientes e as chaves na ordem dos assentos
 * — a chave é o que a reconexão precisa apresentar para voltar ao seu lugar.
 */
async function table(code: string): Promise<{ players: Client[]; keys: string[] }> {
  const first = await Client.open(url);
  first.send({ t: 'host', room: code, game: 'ludo', seats: 4 });
  const opened = await first.joined();
  assert.equal(opened.seats, 4);

  const players = [first];
  const keys = [opened.key];
  for (const seat of [1, 2, 3]) {
    const client = await Client.open(url);
    client.send({ t: 'join', room: code });
    const seated = await client.joined();
    assert.equal(seated.seat, seat);
    // Cada um dos que já estavam vê o novo chegar, e sabe em que lugar.
    for (const earlier of players) {
      assert.deepEqual(await earlier.next(), { t: 'peer', seat });
    }
    players.push(client);
    keys.push(seated.key);
  }
  return { players, keys };
}

describe('relay', () => {
  it('repassa mensagens de jogo nos dois sentidos sem abrir o conteúdo', async () => {
    const { host, guest } = await pair('AAA111');

    host.send({ t: 'msg', d: { t: 'move', p: [12, 28], pr: 0, n: 0 } });
    assert.deepEqual(await guest.next(), {
      t: 'msg',
      d: { t: 'move', p: [12, 28], pr: 0, n: 0 },
      from: 0,
    });

    guest.send({ t: 'msg', d: { t: 'move', p: [52, 36], pr: 0, n: 1 } });
    assert.deepEqual(await host.next(), {
      t: 'msg',
      d: { t: 'move', p: [52, 36], pr: 0, n: 1 },
      from: 1,
    });

    host.close();
    guest.close();
  });

  // A razão de o relay ter mudado: quatro jogadores numa sala só, e cada lance
  // chegando aos outros três assinado por quem o jogou.
  it('leva o lance de um aos outros três, dizendo de quem veio', async () => {
    const { players } = await table('LUDO11');

    players[2]!.send({ t: 'msg', d: { t: 'move', p: [3, 1] } });
    for (const seat of [0, 1, 3]) {
      assert.deepEqual(await players[seat]!.next(), {
        t: 'msg',
        d: { t: 'move', p: [3, 1] },
        from: 2,
      });
    }

    for (const player of players) player.close();
  });

  it('recusa o quinto jogador numa mesa de quatro', async () => {
    const { players } = await table('LUDO12');

    const intruder = await Client.open(url);
    intruder.send({ t: 'join', room: 'LUDO12' });
    const refusal = await intruder.next();
    assert.equal(refusal.t === 'error' && refusal.reason, 'room_full');
    await intruder.closed();

    for (const player of players) player.close();
  });

  it('recusa mesa com gente demais', async () => {
    const client = await Client.open(url);
    client.send({ t: 'host', room: 'BIG001', game: 'ludo', seats: 9 });
    const refusal = await client.next();
    assert.equal(refusal.t === 'error' && refusal.reason, 'bad_seats');
    await client.closed();
  });

  it('responde ao keepalive', async () => {
    const { host, guest } = await pair('AAA112');
    host.send({ t: 'ping' });
    assert.deepEqual(await host.next(), { t: 'pong' });
    host.close();
    guest.close();
  });

  it('avisa quem ficou, dizendo qual assento vagou', async () => {
    const { host, guest } = await pair('AAA113');
    guest.kill();
    assert.deepEqual(await host.next(), { t: 'peer_left', seat: 1 });
    host.close();
  });

  // O caso que justifica o relay: o celular troca de Wi-Fi para 4G no meio da
  // partida e volta para a mesma sala.
  it('deixa quem caiu voltar para o mesmo assento', async () => {
    const { host, guest } = await pair('AAA114');
    guest.kill();
    assert.deepEqual(await host.next(), { t: 'peer_left', seat: 1 });

    const back = await Client.open(url);
    back.send({ t: 'join', room: 'AAA114' });
    const seated = await back.joined();
    assert.equal(seated.seat, 1);
    assert.deepEqual(await host.next(), { t: 'peer', seat: 1 });

    back.send({ t: 'msg', d: { t: 'sync', moves: [] } });
    assert.deepEqual(await host.next(), { t: 'msg', d: { t: 'sync', moves: [] }, from: 1 });

    host.close();
    back.close();
  });

  // Numa mesa de quatro, dois buracos abertos ao mesmo tempo tornam "o assento
  // livre" uma resposta errada: sem a chave, quem volta senta no lugar do outro
  // e passa a jogar com os peões dele.
  it('a chave devolve o assento certo quando há mais de um buraco', async () => {
    const { players, keys } = await table('LUDO13');

    // Derrubados os assentos 1 e 2, o primeiro livre passa a ser o 1 — e quem
    // volta primeiro é o do 2.
    players[1]!.kill();
    players[2]!.kill();
    for (const watching of [0, 3]) {
      const vacated = [await players[watching]!.next(), await players[watching]!.next()]
        .map((message) => (message.t === 'peer_left' ? message.seat : -1))
        .sort();
      assert.deepEqual(vacated, [1, 2], 'quem ficou soube dos dois buracos');
    }

    const back = await Client.open(url);
    back.send({ t: 'join', room: 'LUDO13', key: keys[2] });
    const seated = await back.joined();
    assert.equal(seated.seat, 2, 'a chave manda, não a ordem dos buracos');

    back.close();
    players[0]!.close();
    players[3]!.close();
  });

  it('recusa código que ninguém abriu', async () => {
    const client = await Client.open(url);
    client.send({ t: 'join', room: 'ZZZ999' });
    const refusal = await client.next();
    assert.equal(refusal.t === 'error' && refusal.reason, 'room_not_found');
    await client.closed();
  });

  it('recusa código malformado', async () => {
    const client = await Client.open(url);
    client.send({ t: 'host', room: 'a!', game: 'chess' });
    const refusal = await client.next();
    assert.equal(refusal.t === 'error' && refusal.reason, 'bad_code');
    await client.closed();
  });

  it('derruba quem conecta e não diz a que veio', async () => {
    const client = await Client.open(url);
    const refusal = await client.next();
    assert.equal(refusal.t === 'error' && refusal.reason, 'hello_timeout');
    await client.closed();
  });

  // O health check identifica o processo que respondeu, e é assim que se
  // descobre que existe mais de um: com uma sala aberta, duas chamadas que
  // devolvem `machine` diferentes explicam por que os jogadores não se acham.
  // Sem esse campo, o sintoma é só "código não encontrado".
  it('publica na lista só quem pediu, com lotação, e some quando enche', async () => {
    const address = relay.httpServer.address();
    assert.ok(typeof address === 'object' && address !== null);
    const listing = async () =>
      (await (await fetch(`http://127.0.0.1:${address.port}/rooms`)).json()) as {
        rooms: {
          code: string;
          game: string;
          host: string;
          tc: number;
          seats: number;
          taken: number;
        }[];
      };

    const quiet = await Client.open(url);
    quiet.send({ t: 'host', room: 'QUIET1', game: 'chess' });
    await quiet.next();

    // O apelido chega sujo de propósito: quebra de linha no meio e comprido
    // demais. Ele vai ser desenhado na tela de estranhos, e o cliente que o
    // manda é o menos confiável dos dois lados.
    const open = await Client.open(url);
    open.send({
      t: 'host',
      room: 'OPEN01',
      game: 'checkers',
      listed: true,
      tc: 3,
      name: '  Lucas\nfalso o abridor de salas  ',
    });
    await open.next();

    const before = await listing();
    assert.deepEqual(
      before.rooms.map((room) => room.code),
      ['OPEN01'],
      'a sala sem `listed` fica fora'
    );
    assert.equal(before.rooms[0]?.game, 'checkers');
    assert.equal(before.rooms[0]?.tc, 3);
    assert.equal(before.rooms[0]?.seats, 2);
    assert.equal(before.rooms[0]?.taken, 1, 'a lista sabe dizer 1/2');
    assert.equal(
      before.rooms[0]?.host,
      'Lucasfalso o abrid',
      'o apelido chega limpo e cortado no limite do cartão'
    );

    // Assim que enche, a sala deixa de ser oferecida: anunciá-la só renderia um
    // `room_full` para quem tocasse nela.
    const guest = await Client.open(url);
    guest.send({ t: 'join', room: 'OPEN01' });
    await guest.next();
    assert.deepEqual((await listing()).rooms, []);

    quiet.close();
    open.close();
    guest.close();
  });

  it('publica um health check que identifica o processo', async () => {
    const address = relay.httpServer.address();
    assert.ok(typeof address === 'object' && address !== null);
    const response = await fetch(`http://127.0.0.1:${address.port}/healthz`);
    assert.equal(response.status, 200);
    const body = (await response.json()) as {
      ok: boolean;
      rooms: number;
      machine: string;
    };
    assert.equal(body.ok, true);
    assert.equal(typeof body.rooms, 'number');
    assert.ok(body.machine.length > 0, 'a máquina que respondeu vem no corpo');
  });
});
