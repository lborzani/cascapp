import http from 'node:http';
import { WebSocket, WebSocketServer } from 'ws';

import {
  isValidRoomCode,
  parseClientMessage,
  type ClientMessage,
  type ErrorReason,
  type LiveSummary,
  type RoomSummary,
  type Seat,
  type ServerMessage,
} from './protocol.js';
import {
  isOpen,
  occupied,
  peersOf,
  presentSeats,
  RoomRegistry,
  watchersOf,
  type Room,
  type SeatOutcome,
} from './rooms.js';

/**
 * Relay de partidas: alguns sockets, uma sala, repasse cego.
 *
 * Este processo é o único componente do jogo que precisa de endereço público, e
 * existe por um motivo só: em rede móvel os aparelhos estão atrás de CGNAT e
 * nenhum deles aceita conexão de entrada. Com um ponto de encontro comum, todos
 * discam para fora e o problema desaparece.
 *
 * O servidor não conhece xadrez. Os clientes rodam o mesmo ruleset
 * determinístico e validam cada lance recebido contra a própria lista de lances
 * legais, então um relay comprometido não consegue forjar uma partida — no
 * máximo derrubá-la.
 *
 * A sala tem **N assentos** (2 a 6, escolhidos por quem abre). Eram dois, com
 * nome de papel; o Ludo tem quatro jogadores e um par de nomes não cresce. Ver
 * `protocol.ts`.
 *
 * Fábrica, e não script: `relay.test.ts` sobe uma instância em porta efêmera.
 * Um servidor que só existe como efeito colateral de importar o módulo não tem
 * como ser testado ponta a ponta.
 */

export interface RelayOptions {
  /** Janela de reconexão. Trocar de Wi-Fi para 4G leva segundos; um metrô, mais. */
  roomGraceMs?: number;
  /** Teto absoluto: sala esquecida aberta não vira vazamento de memória. */
  roomMaxMs?: number;
  /** Socket que conecta e não diz a que veio é varrido. */
  helloTimeoutMs?: number;
  sweepIntervalMs?: number;
  pingIntervalMs?: number;
  /** Um lance ocupa ~40 bytes; o sync de uma partida inteira, alguns KB. */
  maxPayload?: number;
  rateWindowMs?: number;
  rateMaxMessages?: number;
  /** Teto da lista pública. Rolagem infinita não é o problema deste jogo. */
  roomListLimit?: number;
  /** Teto de salas na memória. Ver `RoomRegistry`. */
  roomLimit?: number;
}

/**
 * Identifica o processo que respondeu. No Fly vem de `FLY_MACHINE_ID`; fora
 * dele, um número aleatório já serve para distinguir duas instâncias locais.
 */
const MACHINE_ID =
  process.env.FLY_MACHINE_ID ?? `local-${Math.random().toString(36).slice(2, 8)}`;

const DEFAULTS = {
  roomGraceMs: 90_000,
  roomMaxMs: 4 * 60 * 60 * 1000,
  helloTimeoutMs: 10_000,
  sweepIntervalMs: 15_000,
  pingIntervalMs: 25_000,
  maxPayload: 32 * 1024,
  rateWindowMs: 1_000,
  rateMaxMessages: 40,
  roomListLimit: 40,
  // Mil salas são duas mil pessoas jogando ao mesmo tempo, bem acima do que uma
  // máquina compartilhada aguenta em conexões (o `hard_limit` do Fly é 500).
  // O teto não existe para limitar o jogo: existe para o abuso bater num número
  // antes de bater na memória.
  roomLimit: 1_000,
} as const satisfies Required<RelayOptions>;

/**
 * O estado por conexão mora aqui e não em campos enxertados no `WebSocket`,
 * que é de terceiros. Um `WeakMap` some junto com o socket sem `delete`
 * explícito, o que remove a única forma de vazar memória neste processo.
 */
interface Session {
  room: Room<WebSocket> | null;
  seat: Seat | null;
  /** Assiste à sala em `room`, sem assento. */
  watching: boolean;
  alive: boolean;
  helloTimer: NodeJS.Timeout;
  rateStart: number;
  rateCount: number;
}

const ERROR_DETAIL: Record<
  'room_taken' | 'room_not_found' | 'room_full' | 'bad_seats' | 'too_many_rooms',
  string
> = {
  room_taken: 'Já existe uma partida com esse código.',
  room_not_found: 'Nenhuma partida com esse código.',
  room_full: 'Essa partida já está cheia.',
  bad_seats: 'Número de jogadores fora do que o servidor aceita.',
  too_many_rooms: 'O servidor está cheio. Tente de novo em alguns minutos.',
};

export interface Relay {
  readonly httpServer: http.Server;
  listen(port: number, host?: string): Promise<number>;
  close(): Promise<void>;
  readonly roomCount: number;
}

export function createRelay(options: RelayOptions = {}): Relay {
  const config = { ...DEFAULTS, ...options };
  const sessions = new WeakMap<WebSocket, Session>();
  const registry = new RoomRegistry<WebSocket>(
    config.roomGraceMs,
    config.roomMaxMs,
    config.roomLimit
  );

  const httpServer = http.createServer((request, response) => {
    // Lista pública de salas esperando alguém. Só entra quem pediu para
    // aparecer: uma partida aberta para um amigo continua invisível, e o código
    // continua sendo o segredo que ela sempre foi.
    if (request.url === '/rooms') {
      const rooms: RoomSummary[] = registry
        .listPublic(config.roomListLimit)
        .map((room) => ({
          code: room.code,
          game: room.game,
          host: room.host,
          tc: room.tc,
          age: Math.round((Date.now() - room.createdAt) / 1000),
          seats: room.capacity,
          taken: occupied(room),
        }));
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify({ rooms }));
      return;
    }
    // Partidas públicas em andamento, para quem quer assistir. Mesmo critério de
    // privacidade de `/rooms`: só aparece quem abriu a sala pedindo para aparecer.
    if (request.url === '/live') {
      const rooms: LiveSummary[] = registry
        .listLive(config.roomListLimit)
        .map((room) => ({
          code: room.code,
          game: room.game,
          host: room.host,
          tc: room.tc,
          age: Math.round((Date.now() - room.createdAt) / 1000),
          seats: room.capacity,
          taken: occupied(room),
          watchers: watchersOf(room).length,
        }));
      response.writeHead(200, { 'content-type': 'application/json' });
      response.end(JSON.stringify({ rooms }));
      return;
    }
    if (request.url === '/healthz') {
      response.writeHead(200, { 'content-type': 'application/json' });
      // `machine` responde à única pergunta que este serviço não consegue
      // responder sozinho: quantos processos existem. As salas moram na memória
      // de um deles, então dois processos atrás do mesmo endereço colocam os
      // jogadores em lados opostos de um muro — e o sintoma, do lado do
      // jogador, é "nenhuma partida com esse código", que parece erro de
      // digitação. Duas chamadas a /healthz devolvendo `machine` diferentes
      // custam menos que uma tarde entendendo isso.
      response.end(
        JSON.stringify({ ok: true, rooms: registry.size, machine: MACHINE_ID })
      );
      return;
    }
    response.writeHead(404);
    response.end();
  });

  const wss = new WebSocketServer({
    server: httpServer,
    path: '/ws',
    maxPayload: config.maxPayload,
  });

  wss.on('connection', (socket: WebSocket) => {
    const session: Session = {
      room: null,
      seat: null,
      watching: false,
      alive: true,
      helloTimer: setTimeout(() => {
        if (session.room === null) {
          fail(socket, 'hello_timeout', 'Nenhuma sala foi informada.');
        }
      }, config.helloTimeoutMs),
      rateStart: Date.now(),
      rateCount: 0,
    };
    sessions.set(socket, session);

    socket.on('pong', () => {
      session.alive = true;
    });

    socket.on('message', (raw) => {
      if (rateLimited(session)) {
        fail(socket, 'rate_limited', 'Mensagens demais.');
        return;
      }
      const message = parseClientMessage(raw.toString());
      if (message === null) return;
      handle(socket, session, message);
    });

    socket.on('close', () => {
      clearTimeout(session.helloTimer);
      releaseSeat(socket, session);
    });

    socket.on('error', () => socket.terminate());
  });

  function handle(socket: WebSocket, session: Session, message: ClientMessage): void {
    if (session.room === null) {
      switch (message.t) {
        case 'host':
          claimSeat(socket, session, message.room, (code) =>
            registry.openRoom(
              code,
              message.game,
              socket,
              message.listed,
              message.tc,
              message.seats,
              message.name
            )
          );
          break;
        case 'join':
          claimSeat(socket, session, message.room, (code) =>
            registry.joinRoom(code, socket, message.key)
          );
          break;
        case 'watch':
          watch(socket, session, message.room);
          break;
        default:
          fail(socket, 'not_in_room', 'Entre em uma sala antes de enviar mensagens.');
      }
      return;
    }

    switch (message.t) {
      case 'msg': {
        // Para todos os outros, e com a assinatura de quem falou. Com dois
        // assentos "o outro" era um endereço; com quatro, quem recebe precisa
        // saber de quem veio para saber de quem é a vez.
        //
        // Espectador não tem assento e cai aqui: o que ele manda não sai para
        // ninguém. É isso que deixa a sala aberta a quem só tem o código sem
        // abrir a partida a um lance, um `bye` ou um `sync` forjado por ele.
        if (session.seat === null) break;
        const relayed: ServerMessage = { t: 'msg', d: message.d, from: session.seat };
        for (const peer of peersOf(session.room, session.seat)) {
          send(peer, relayed);
        }
        for (const watcher of watchersOf(session.room)) {
          send(watcher, relayed);
        }
        break;
      }
      case 'ping':
        send(socket, { t: 'pong' });
        break;
      case 'leave':
        socket.close(1000, 'leave');
        break;
      default:
        break;
    }
  }

  function claimSeat(
    socket: WebSocket,
    session: Session,
    rawCode: string,
    claim: (code: string) => SeatOutcome<WebSocket>
  ): void {
    const code = rawCode.toUpperCase();
    if (!isValidRoomCode(code)) {
      fail(socket, 'bad_code', 'Código de sala inválido.');
      return;
    }
    const outcome = claim(code);
    if (!outcome.ok) {
      fail(socket, outcome.reason, ERROR_DETAIL[outcome.reason]);
      return;
    }

    clearTimeout(session.helloTimer);
    session.room = outcome.room;
    session.seat = outcome.seat;
    // O socket antigo do mesmo assento é um zumbi que a rede móvel deixou para
    // trás; derrubá-lo evita que o `close` dele apague o assento novo.
    if (outcome.evicted !== null) {
      const stale = sessions.get(outcome.evicted);
      if (stale !== undefined) stale.room = null;
      outcome.evicted.terminate();
    }

    send(socket, {
      t: 'joined',
      seat: outcome.seat,
      game: outcome.room.game,
      seats: outcome.room.capacity,
      present: presentSeats(outcome.room),
      key: outcome.key,
      watchers: watchersOf(outcome.room).length,
    });
    for (const peer of peersOf(outcome.room, outcome.seat)) {
      send(peer, { t: 'peer', seat: outcome.seat });
    }
    for (const watcher of watchersOf(outcome.room)) {
      send(watcher, { t: 'peer', seat: outcome.seat });
    }
  }

  function watch(socket: WebSocket, session: Session, rawCode: string): void {
    const code = rawCode.toUpperCase();
    if (!isValidRoomCode(code)) {
      fail(socket, 'bad_code', 'Código de sala inválido.');
      return;
    }
    const outcome = registry.watchRoom(code, socket);
    if (!outcome.ok) {
      fail(
        socket,
        outcome.reason,
        outcome.reason === 'watch_full'
          ? 'Essa partida já tem espectadores demais.'
          : ERROR_DETAIL.room_not_found
      );
      return;
    }
    clearTimeout(session.helloTimer);
    session.room = outcome.room;
    session.watching = true;
    const watchers = watchersOf(outcome.room).length;
    send(socket, {
      t: 'watching',
      game: outcome.room.game,
      seats: outcome.room.capacity,
      present: presentSeats(outcome.room),
      watchers,
    });
    announceWatchers(outcome.room);
  }

  /** O contador dos jogadores. Vai inteiro, e não como "+1": um aviso perdido não deixa o número errado para sempre. */
  function announceWatchers(room: Room<WebSocket>): void {
    const n = watchersOf(room).length;
    for (const seated of room.seats) {
      if (seated !== null) send(seated, { t: 'watchers', n });
    }
  }

  function releaseSeat(socket: WebSocket, session: Session): void {
    const { room, seat } = session;
    if (room !== null && session.watching) {
      session.room = null;
      registry.unwatch(room, socket);
      announceWatchers(room);
      return;
    }
    if (room === null || seat === null) return;
    session.room = null;

    // Um socket já substituído por uma reconexão não ocupa mais o assento, e
    // `release` o ignora — sem isso o zumbi anunciaria a saída de quem acabou
    // de voltar, e os outros veriam "jogador saiu" no meio da partida.
    for (const peer of registry.release(room, seat, socket)) {
      send(peer, { t: 'peer_left', seat });
    }
    for (const watcher of watchersOf(room)) {
      send(watcher, { t: 'peer_left', seat });
    }
  }

  function send(socket: WebSocket, payload: ServerMessage): void {
    if (isOpen(socket)) {
      socket.send(JSON.stringify(payload));
    }
  }

  function fail(socket: WebSocket, reason: ErrorReason, detail: string): void {
    send(socket, { t: 'error', reason, detail });
    socket.close(1008, reason);
  }

  function rateLimited(session: Session): boolean {
    const now = Date.now();
    if (now - session.rateStart > config.rateWindowMs) {
      session.rateStart = now;
      session.rateCount = 0;
    }
    session.rateCount += 1;
    return session.rateCount > config.rateMaxMessages;
  }

  /** Sockets mortos em rede móvel não fecham sozinhos; o ping é quem os acha. */
  const pingTimer = setInterval(() => {
    for (const socket of wss.clients) {
      const session = sessions.get(socket);
      if (session === undefined) continue;
      if (!session.alive) {
        socket.terminate();
        continue;
      }
      session.alive = false;
      socket.ping();
    }
  }, config.pingIntervalMs);
  pingTimer.unref();

  const sweepTimer = setInterval(() => {
    for (const room of registry.sweep()) {
      for (const seated of room.seats) {
        seated?.terminate();
      }
      for (const watcher of room.watchers) {
        watcher.terminate();
      }
    }
  }, config.sweepIntervalMs);
  sweepTimer.unref();

  return {
    httpServer,
    get roomCount() {
      return registry.size;
    },
    listen(port, host = '0.0.0.0') {
      return new Promise((resolve) => {
        httpServer.listen(port, host, () => {
          const address = httpServer.address();
          resolve(typeof address === 'object' && address !== null ? address.port : port);
        });
      });
    },
    close() {
      clearInterval(pingTimer);
      clearInterval(sweepTimer);
      for (const socket of wss.clients) {
        socket.terminate();
      }
      return new Promise((resolve) => {
        wss.close(() => httpServer.close(() => resolve()));
      });
    },
  };
}
