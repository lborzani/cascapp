import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { isValidRoomCode, isValidSeatCount, parseClientMessage } from './protocol.js';
import { occupied, OPEN, presentSeats, RoomRegistry } from './rooms.js';

/** Socket de mentira: o registro só pergunta se ele está aberto. */
class FakeSocket {
  constructor(public readyState: number = OPEN) {}

  kill(): void {
    this.readyState = 3; // CLOSED
  }
}

/** Chaves previsíveis, para o teste poder falar sobre uma delas. */
function registry(now: () => number = Date.now, roomLimit = 1_000): RoomRegistry<FakeSocket> {
  let issued = 0;
  return new RoomRegistry<FakeSocket>(
    90_000,
    4 * 60 * 60 * 1000,
    roomLimit,
    now,
    () => `k${issued++}`
  );
}

describe('RoomRegistry', () => {
  it('recusa salas novas depois do teto, e ainda assim deixa voltar às antigas', () => {
    const rooms = registry(Date.now, 2);
    const first = new FakeSocket();
    const second = new FakeSocket();

    assert.equal(rooms.openRoom('AAA111', 'chess', first).ok, true);
    assert.equal(rooms.openRoom('BBB222', 'chess', second).ok, true);

    const overflow = rooms.openRoom('CCC333', 'chess', new FakeSocket());
    assert.equal(overflow.ok, false);
    assert.equal(!overflow.ok && overflow.reason, 'too_many_rooms');

    // Abrir sala é o que o teto barra; **voltar** para uma sala que já existe não
    // cria nada, e barrar isso mataria a reconexão de quem já estava jogando.
    first.kill();
    assert.equal(rooms.openRoom('AAA111', 'chess', new FakeSocket()).ok, true);
  });

  it('junta dois jogadores na mesma sala', () => {
    const rooms = registry();
    const host = new FakeSocket();
    const guest = new FakeSocket();

    const opened = rooms.openRoom('ABC123', 'chess', host);
    assert.equal(opened.ok, true);
    assert.equal(opened.ok && opened.seat, 0, 'quem abre senta no assento 0');

    const joined = rooms.joinRoom('ABC123', guest);
    assert.equal(joined.ok, true);
    assert.equal(joined.ok && joined.seat, 1);
    assert.equal(joined.ok && joined.room.seats[0], host);
    assert.equal(joined.ok && joined.room.seats[1], guest);
  });

  // O que o Ludo precisa: a sala nasce com quatro lugares e enche em ordem.
  it('abre sala de quatro e senta cada um no seu lugar', () => {
    const rooms = registry();
    rooms.openRoom('LUDO01', 'ludo', new FakeSocket(), false, 0, 4);
    for (const expected of [1, 2, 3]) {
      const seated = rooms.joinRoom('LUDO01', new FakeSocket());
      assert.equal(seated.ok && seated.seat, expected);
    }

    const room = rooms.get('LUDO01');
    assert.ok(room);
    assert.equal(room.capacity, 4);
    assert.deepEqual(presentSeats(room), [0, 1, 2, 3]);

    const extra = rooms.joinRoom('LUDO01', new FakeSocket());
    assert.equal(extra.ok === false && extra.reason, 'room_full');
  });

  it('recusa capacidade fora da faixa', () => {
    const rooms = registry();
    const tooMany = rooms.openRoom('BIG001', 'ludo', new FakeSocket(), false, 0, 9);
    assert.equal(tooMany.ok === false && tooMany.reason, 'bad_seats');

    const alone = rooms.openRoom('ONE001', 'chess', new FakeSocket(), false, 0, 1);
    assert.equal(alone.ok === false && alone.reason, 'bad_seats', 'sozinho não é partida');
    assert.equal(rooms.size, 0, 'e a sala recusada não fica no registro');
  });

  it('recusa um segundo anfitrião enquanto o primeiro está vivo', () => {
    const rooms = registry();
    rooms.openRoom('ABC123', 'chess', new FakeSocket());

    const clash = rooms.openRoom('ABC123', 'chess', new FakeSocket());
    assert.equal(clash.ok, false);
    assert.equal(clash.ok === false && clash.reason, 'room_taken');
  });

  it('recusa um terceiro jogador numa sala de dois', () => {
    const rooms = registry();
    rooms.openRoom('ABC123', 'chess', new FakeSocket());
    rooms.joinRoom('ABC123', new FakeSocket());

    const extra = rooms.joinRoom('ABC123', new FakeSocket());
    assert.equal(extra.ok, false);
    assert.equal(extra.ok === false && extra.reason, 'room_full');
  });

  it('não conhece sala que ninguém abriu', () => {
    const rooms = registry();
    const missing = rooms.joinRoom('ZZZ999', new FakeSocket());
    assert.equal(missing.ok, false);
    assert.equal(missing.ok === false && missing.reason, 'room_not_found');
  });

  // O caso que justifica o relay inteiro: o celular troca de Wi-Fi para 4G, o
  // socket morre, e o mesmo jogador volta com o mesmo código.
  it('devolve o assento a quem caiu e voltou', () => {
    const rooms = registry();
    const host = new FakeSocket();
    const guest = new FakeSocket();
    rooms.openRoom('ABC123', 'chess', host);
    rooms.joinRoom('ABC123', guest);

    guest.kill();
    const room = rooms.get('ABC123');
    assert.ok(room);
    rooms.release(room, 1, guest);

    const back = new FakeSocket();
    const rejoined = rooms.joinRoom('ABC123', back);
    assert.equal(rejoined.ok, true);
    assert.equal(rejoined.ok && rejoined.room.seats[1], back);
    assert.equal(rejoined.ok && rejoined.room.seats[0], host, 'o assento 0 não é perturbado');
  });

  // Com quatro lugares, "o assento livre" deixa de identificar alguém: dois
  // jogadores caídos deixam dois buracos, e sem a chave o primeiro a voltar
  // senta no lugar do outro — e joga com os peões dele.
  it('a chave leva de volta ao mesmo assento, e não ao primeiro livre', () => {
    const rooms = registry();
    rooms.openRoom('LUDO02', 'ludo', new FakeSocket(), false, 0, 4);
    const second = rooms.joinRoom('LUDO02', new FakeSocket());
    const third = rooms.joinRoom('LUDO02', new FakeSocket());
    assert.ok(second.ok && third.ok);

    const room = rooms.get('LUDO02');
    assert.ok(room);
    const socketTwo = room.seats[1];
    const socketThree = room.seats[2];
    assert.ok(socketTwo && socketThree);
    socketTwo.kill();
    socketThree.kill();
    rooms.release(room, 1, socketTwo);
    rooms.release(room, 2, socketThree);

    // Quem volta é o do assento 2, e o primeiro assento livre é o 1.
    const back = new FakeSocket();
    const rejoined = rooms.joinRoom('LUDO02', back, third.key);
    assert.equal(rejoined.ok && rejoined.seat, 2, 'a chave manda, não a ordem');
    assert.equal(room.seats[1], null, 'o assento do outro continua esperando por ele');
  });

  it('chave desconhecida cai no primeiro assento livre', () => {
    const rooms = registry();
    rooms.openRoom('ABC124', 'chess', new FakeSocket());
    const seated = rooms.joinRoom('ABC124', new FakeSocket(), 'chave-de-outra-sala');
    assert.equal(seated.ok && seated.seat, 1);
  });

  // Sem troca de chave, a cadeira que muda de dono continua abrindo com a chave
  // do dono anterior: ele volta e derruba quem sentou, o derrubado reconecta com
  // a mesma chave e derruba de volta — dois aparelhos se expulsando a cada meio
  // segundo, e uma partida que não anda para nenhum dos dois.
  it('quem senta sem chave ganha chave nova, e a do dono anterior deixa de abrir o assento', () => {
    const rooms = registry();
    rooms.openRoom('TROCA1', 'uno', new FakeSocket(), false, 0, 4);
    const first = rooms.joinRoom('TROCA1', new FakeSocket());
    assert.ok(first.ok);
    const room = rooms.get('TROCA1');
    assert.ok(room);
    const gone = room.seats[1];
    assert.ok(gone);
    gone.kill();
    rooms.release(room, 1, gone);

    const stranger = new FakeSocket();
    const took = rooms.joinRoom('TROCA1', stranger);
    assert.equal(took.ok && took.seat, 1);
    assert.notEqual(took.ok && took.key, first.key, 'o novo dono não herda a chave');

    const returning = rooms.joinRoom('TROCA1', new FakeSocket(), first.key);
    assert.equal(returning.ok && returning.seat, 2, 'a chave antiga não abre mais o assento 1');
    assert.equal(room.seats[1], stranger, 'e quem sentou nele não é derrubado');
  });

  it('quem volta com a própria chave continua com ela', () => {
    const rooms = registry();
    rooms.openRoom('VOLTA1', 'uno', new FakeSocket(), false, 0, 4);
    const first = rooms.joinRoom('VOLTA1', new FakeSocket());
    assert.ok(first.ok);
    const room = rooms.get('VOLTA1');
    assert.ok(room);
    const gone = room.seats[1];
    assert.ok(gone);
    gone.kill();
    rooms.release(room, 1, gone);

    const back = rooms.joinRoom('VOLTA1', new FakeSocket(), first.key);
    assert.equal(back.ok && back.seat, 1);
    // A chave fica em disco no aparelho. Se ela mudasse a cada volta, a próxima
    // queda antes de a cópia em disco ser regravada perderia o assento.
    assert.equal(back.ok && back.key, first.key);
  });

  it('entrega o socket zumbi para o chamador derrubar', () => {
    const rooms = registry();
    const stale = new FakeSocket();
    rooms.openRoom('ABC123', 'chess', stale);
    stale.kill();

    const fresh = rooms.openRoom('ABC123', 'chess', new FakeSocket());
    assert.equal(fresh.ok, true);
    assert.equal(fresh.ok && fresh.evicted, stale);
  });

  // Um socket substituído por uma reconexão não pode anunciar a saída de quem
  // acabou de voltar: seria "jogador saiu" no meio da partida.
  it('ignora a liberação vinda de um socket já substituído', () => {
    const rooms = registry();
    const host = new FakeSocket();
    rooms.openRoom('ABC123', 'chess', host);
    const stale = new FakeSocket();
    rooms.joinRoom('ABC123', stale);
    stale.kill();
    const room = rooms.get('ABC123');
    assert.ok(room);
    rooms.release(room, 1, stale);

    const back = new FakeSocket();
    rooms.joinRoom('ABC123', back);
    rooms.release(room, 1, stale); // o close atrasado do zumbi

    assert.equal(room.seats[1], back);
    assert.equal(room.emptySince, null);
  });

  it('avisa os outros três quando um sai', () => {
    const rooms = registry();
    rooms.openRoom('LUDO03', 'ludo', new FakeSocket(), false, 0, 4);
    rooms.joinRoom('LUDO03', new FakeSocket());
    rooms.joinRoom('LUDO03', new FakeSocket());
    rooms.joinRoom('LUDO03', new FakeSocket());

    const room = rooms.get('LUDO03');
    assert.ok(room);
    const leaving = room.seats[2];
    assert.ok(leaving);
    const remaining = rooms.release(room, 2, leaving);
    assert.equal(remaining.length, 3, 'todo mundo que ficou precisa saber');
    assert.equal(occupied(room), 3);
  });

  it('só apaga a sala vazia depois da carência', () => {
    let clock = 1_000;
    const rooms = registry(() => clock);
    const host = new FakeSocket();
    rooms.openRoom('ABC123', 'chess', host);
    const room = rooms.get('ABC123');
    assert.ok(room);

    host.kill();
    rooms.release(room, 0, host);

    clock += 60_000;
    assert.equal(rooms.sweep().length, 0, 'ainda dentro da janela de reconexão');
    assert.equal(rooms.size, 1);

    clock += 60_000;
    assert.equal(rooms.sweep().length, 1);
    assert.equal(rooms.size, 0);
  });

  // A lista pública é opt-in, e o padrão é ficar de fora. Uma partida aberta
  // para um amigo não pode aparecer para estranhos por omissão.
  it('só lista quem pediu para ser listado', () => {
    const rooms = registry();
    rooms.openRoom('PRIV01', 'chess', new FakeSocket());
    rooms.openRoom('PUB001', 'chess', new FakeSocket(), true, 2);

    const listed = rooms.listPublic(10);
    assert.equal(listed.length, 1);
    assert.equal(listed[0]?.code, 'PUB001');
    assert.equal(listed[0]?.tc, 2, 'o ritmo viaja junto, para a lista mostrar');
  });

  it('esconde sala cheia e sala sem ninguém', () => {
    const rooms = registry();
    const lonely = new FakeSocket();
    rooms.openRoom('FULL01', 'chess', new FakeSocket(), true);
    rooms.joinRoom('FULL01', new FakeSocket());
    rooms.openRoom('DEAD01', 'chess', lonely, true);
    lonely.kill();

    assert.deepEqual(rooms.listPublic(10).map((room) => room.code), []);
  });

  // Uma sala de quatro com dois dentro continua valendo o anúncio: é o caso em
  // que a lista mais serve, porque a partida ainda precisa de gente.
  it('mantém na lista a sala de quatro que ainda tem lugar', () => {
    const rooms = registry();
    rooms.openRoom('LUDO04', 'ludo', new FakeSocket(), true, 0, 4);
    rooms.joinRoom('LUDO04', new FakeSocket());

    const listed = rooms.listPublic(10);
    assert.equal(listed.length, 1);
    assert.equal(listed[0]?.capacity, 4);
    assert.equal(occupied(listed[0]!), 2, 'a lista sabe dizer 2/4');
  });

  it('lista a mais nova primeiro e respeita o teto', () => {
    let clock = 1_000;
    const rooms = registry(() => clock);
    for (const code of ['AAA001', 'BBB002', 'CCC003']) {
      rooms.openRoom(code, 'chess', new FakeSocket(), true);
      clock += 1_000;
    }
    assert.deepEqual(
      rooms.listPublic(2).map((room) => room.code),
      ['CCC003', 'BBB002'],
      'quem acabou de abrir está olhando para a tela agora'
    );
  });

  it('apaga sala velha mesmo com gente dentro', () => {
    let clock = 1_000;
    const rooms = registry(() => clock);
    rooms.openRoom('ABC123', 'chess', new FakeSocket());

    clock += 5 * 60 * 60 * 1000;
    assert.equal(rooms.sweep().length, 1);
  });
});

describe('protocolo', () => {
  it('aceita só códigos plausíveis', () => {
    assert.equal(isValidRoomCode('ABC123'), true);
    assert.equal(isValidRoomCode('abc123'), false, 'o servidor normaliza antes de validar');
    assert.equal(isValidRoomCode('AB'), false);
    assert.equal(isValidRoomCode('ABC-123'), false);
    assert.equal(isValidRoomCode(''), false);
  });

  it('aceita só quantidades de jogador que são uma partida', () => {
    assert.equal(isValidSeatCount(2), true);
    assert.equal(isValidSeatCount(4), true);
    assert.equal(isValidSeatCount(1), false);
    assert.equal(isValidSeatCount(7), false);
    assert.equal(isValidSeatCount(2.5), false);
  });

  it('devolve null para qualquer coisa que não seja do protocolo', () => {
    assert.equal(parseClientMessage('não é json'), null);
    assert.equal(parseClientMessage('"texto solto"'), null);
    assert.equal(parseClientMessage('null'), null);
    assert.equal(parseClientMessage('{"t":"desconhecido"}'), null);
    assert.equal(parseClientMessage('{"t":"host"}'), null, 'host sem sala');
    assert.equal(parseClientMessage('{"t":"join","room":7}'), null, 'sala não-texto');
  });

  // Um cliente escrito antes do Ludo não manda `seats` nem `key`, e o que ele
  // queria dizer com isso é "dois jogadores, primeira entrada". Um escrito antes
  // do apelido não manda `name`, e a sala dele entra sem dono nomeado — que é
  // como todas as salas eram.
  it('trata cliente antigo como sala de dois', () => {
    assert.deepEqual(parseClientMessage('{"t":"host","room":"ABC123","game":"chess"}'), {
      t: 'host',
      room: 'ABC123',
      game: 'chess',
      listed: false,
      tc: 0,
      seats: 2,
      name: '',
    });
    assert.deepEqual(parseClientMessage('{"t":"join","room":"ABC123"}'), {
      t: 'join',
      room: 'ABC123',
      key: '',
    });
  });

  it('deixa o conteúdo do jogo passar sem abrir', () => {
    const parsed = parseClientMessage('{"t":"msg","d":{"t":"move","p":[12,28]}}');
    assert.deepEqual(parsed, { t: 'msg', d: { t: 'move', p: [12, 28] } });
  });
});
