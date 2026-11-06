import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import type { Account, TokenVerifier } from './accounts.js';
import { cleanIds, MAX_FRIENDS, parseClientMessage } from './protocol.js';
import { createRelay, type Relay } from './server.js';
import { Client } from './testing.js';

const ANA: Account = { id: 'anaanaanaana123', name: 'Ana', avatar: '', elo: 1200 };
const BIA: Account = { id: 'biabiabiabia123', name: 'Bia', avatar: '', elo: 1200 };
const CAI: Account = { id: 'caicaicaicai123', name: 'Cai', avatar: '', elo: 1200 };
const DAN: Account = { id: 'dandandandan123', name: 'Dan', avatar: '', elo: 1200 };
const ACCOUNTS: Record<string, Account> = { ana: ANA, bia: BIA, cai: CAI, dan: DAN };
const verifyToken: TokenVerifier = async (token) => ACCOUNTS[token] ?? null;

let relay: Relay;
let url: string;
const open: Client[] = [];

before(async () => {
  relay = createRelay({ helloTimeoutMs: 500, roomGraceMs: 60_000, verifyToken });
  const port = await relay.listen(0, '127.0.0.1');
  url = `ws://127.0.0.1:${port}/ws`;
});

after(async () => {
  for (const client of open) client.close();
  await relay.close();
});

async function connect(): Promise<Client> {
  const client = await Client.open(url);
  open.push(client);
  return client;
}

/** Abre a presença e devolve o socket já com a primeira lista lida. */
async function present(token: string, friends: Account[]): Promise<{ client: Client; online: string[] }> {
  const client = await connect();
  client.send({ t: 'presence', token, friends: friends.map((friend) => friend.id) });
  const first = await client.nextOf('friends');
  return { client, online: first.online.map((friend) => friend.id) };
}

/** Fecha e dá tempo de o relay ver o `close`: o teste seguinte não herda ninguém online. */
async function closeAll(clients: Client[]): Promise<void> {
  for (const client of clients) client.close();
  await new Promise((resolve) => setTimeout(resolve, 50));
}

async function who(client: Client, friends: Account[]) {
  client.send({ t: 'who', friends: friends.map((friend) => friend.id) });
  return (await client.nextOf('friends')).online;
}

describe('presença: protocolo', () => {
  it('ids de forma estranha somem, repetidos contam uma vez, a lista tem teto', () => {
    assert.deepEqual(cleanIds([ANA.id, ANA.id, 'curto', 42, BIA.id]), [ANA.id, BIA.id]);
    assert.deepEqual(cleanIds('nada'), []);
    const many = Array.from({ length: 300 }, (_, i) => String(i).padStart(15, 'a'));
    assert.equal(cleanIds(many).length, MAX_FRIENDS);
  });

  it('presença sem token e convite sem destino válido não entram', () => {
    assert.equal(parseClientMessage(JSON.stringify({ t: 'presence', friends: [] })), null);
    assert.equal(parseClientMessage(JSON.stringify({ t: 'invite', to: 'x', game: 'chess', room: 'ABCD23' })), null);
    assert.equal(parseClientMessage(JSON.stringify({ t: 'invite', to: ANA.id, game: 'chess', room: '!' })), null);
    assert.deepEqual(parseClientMessage(JSON.stringify({ t: 'invite', to: ANA.id, game: 'Chess', room: 'abcd23' })), {
      t: 'invite',
      to: ANA.id,
      game: 'chess',
      room: 'ABCD23',
    });
  });
});

describe('presença: ponta a ponta', () => {
  it('token que a conta não confirma é recusado', async () => {
    const client = await connect();
    client.send({ t: 'presence', token: 'ninguem', friends: [] });
    const error = await client.nextOf('error');
    assert.equal(error.reason, 'bad_token');
  });

  it('amigos mútuos se veem; quem só lista de um lado não vê nada', async () => {
    const ana = await present('ana', [BIA, CAI]);
    assert.deepEqual(ana.online, []);
    const bia = await present('bia', [ANA]);
    assert.deepEqual(bia.online, [ANA.id]);
    // Cai lista a Ana, mas a Ana… também lista o Cai. Mútuo: se veem.
    const cai = await present('cai', [ANA]);
    assert.deepEqual(cai.online, [ANA.id]);
    // O Dan lista a Ana, e ela não lista o Dan: nenhum dos dois descobre o outro.
    const dan = await present('dan', [ANA]);
    assert.deepEqual(dan.online, []);
    const seen = (await who(ana.client, [BIA, CAI])).map((friend) => friend.id).sort();
    assert.deepEqual(seen, [BIA.id, CAI.id].sort());
    assert.deepEqual(await who(dan.client, [ANA]), []);
    // A Ana passa a listar o Dan (amigo novo): vale no próximo `who` dos dois.
    assert.deepEqual((await who(ana.client, [BIA, CAI, DAN])).length, 3);
    assert.deepEqual((await who(dan.client, [ANA])).map((friend) => friend.id), [ANA.id]);
    await closeAll([ana, bia, cai, dan].map((entry) => entry.client));
  });

  it('fechar o app tira do online', async () => {
    const ana = await present('ana', [BIA]);
    const bia = await present('bia', [ANA]);
    assert.deepEqual(await who(ana.client, [BIA]).then((list) => list.map((f) => f.id)), [BIA.id]);
    await closeAll([bia.client]);
    assert.deepEqual(await who(ana.client, [BIA]), []);
    await closeAll([ana.client]);
  });

  it('amigo sentado aparece com jogo e sala; jogando só com a mesa cheia', async () => {
    const ana = await present('ana', [BIA]);
    const bia = await present('bia', [ANA]);
    const host = await connect();
    host.send({ t: 'host', room: 'PRES23', game: 'chess', listed: false, tc: 0, seats: 2, name: '', token: 'bia' });
    await host.nextOf('identity');
    assert.deepEqual(await who(ana.client, [BIA]), [{ id: BIA.id, game: 'chess', room: 'PRES23', playing: false }]);

    const guest = await connect();
    guest.send({ t: 'join', room: 'PRES23', key: '', token: '' });
    await guest.nextOf('joined');
    assert.deepEqual(await who(ana.client, [BIA]), [{ id: BIA.id, game: 'chess', room: 'PRES23', playing: true }]);

    host.close();
    await new Promise((resolve) => setTimeout(resolve, 50));
    assert.deepEqual(await who(ana.client, [BIA]), [{ id: BIA.id, game: '', room: '', playing: false }]);
    await closeAll([ana.client, bia.client, guest]);
  });

  it('convite chega em todo aparelho do amigo mútuo, e só nele', async () => {
    const ana = await present('ana', [BIA, DAN]);
    const bia = await present('bia', [ANA]);
    const bia2 = await present('bia', [ANA]);
    const dan = await present('dan', []);

    ana.client.send({ t: 'invite', to: BIA.id, game: 'chess', room: 'CONV23' });
    for (const target of [bia, bia2]) {
      assert.deepEqual(await target.client.nextOf('invited'), { t: 'invited', from: ANA.id, game: 'chess', room: 'CONV23' });
    }
    // O Dan não lista a Ana: o convite dela não chega.
    ana.client.send({ t: 'invite', to: DAN.id, game: 'chess', room: 'CONV23' });
    await dan.client.quiet();
    // E a Bia não convida quem não está na lista dela.
    bia.client.send({ t: 'invite', to: DAN.id, game: 'chess', room: 'CONV23' });
    await dan.client.quiet();
    await closeAll([ana, bia, bia2, dan].map((entry) => entry.client));
  });

  it('presença não abre sala nem aparece na lista pública', async () => {
    const before = relay.roomCount;
    const ana = await present('ana', []);
    assert.equal(relay.roomCount, before);
    ana.client.send({ t: 'msg', d: 'oi' });
    await ana.client.quiet();
    ana.client.close();
  });
});
