import { randomUUID } from 'node:crypto';

import { isValidSeatCount, MIN_SEATS, type Seat } from './protocol.js';

/**
 * Registro de salas, separado do transporte para poder ser testado sem abrir
 * socket nenhum. Só depende de `OpenState`, que é o mínimo que um socket
 * precisa expor para responder "você ainda está vivo?".
 *
 * A sala tem **N assentos**, e não anfitrião e convidado. Ver `protocol.ts`
 * para o porquê; aqui a consequência é que um assento é um índice num array, e
 * "o outro lado" virou "os outros".
 */

export interface OpenState {
  readonly readyState: number;
}

/** Mesmo valor de `WebSocket.OPEN`, sem importar `ws` só por uma constante. */
export const OPEN = 1;

export interface Room<S extends OpenState> {
  readonly code: string;
  readonly game: string;
  /** Aparece na lista pública. Falso salvo pedido explícito de quem abriu. */
  readonly listed: boolean;
  /** Índice do ritmo do lado do jogo; o servidor só repassa. */
  readonly tc: number;
  /** Quantos jogadores esta partida quer. Decidido por quem abriu. */
  readonly capacity: number;
  /**
   * Apelido de quem abriu, já limpo na fronteira. Só serve à lista pública —
   * numa sala privada ele é guardado e nunca sai daqui.
   *
   * Fixo depois de aberta: quem voltar ao assento 0 depois de uma queda não
   * renomeia a sala que os outros já estão vendo na lista.
   */
  readonly host: string;
  readonly seats: (S | null)[];
  /**
   * Segredo por assento, entregue a quem o ocupou. É o que permite voltar para
   * o **mesmo** lugar depois de uma queda — com dois assentos bastava pegar o
   * livre, com quatro isso trocaria dois jogadores de lugar.
   *
   * Muda quando o assento muda de dono (ver `joinRoom`), e só nessa hora: quem
   * volta com a própria chave continua com ela, porque é a cópia em disco no
   * aparelho que vai trazê-lo de volta na próxima queda.
   */
  readonly keys: string[];
  readonly createdAt: number;
  /**
   * Momento em que a sala ficou sem ninguém. `null` enquanto houver alguém.
   * Uma sala vazia **não** é apagada na hora: os jogadores podem ter caído
   * juntos porque a rede caiu, e voltam com o mesmo código.
   */
  emptySince: number | null;
}

export type SeatOutcome<S extends OpenState> =
  | { ok: true; room: Room<S>; seat: Seat; key: string; evicted: S | null }
  | {
      ok: false;
      reason: 'room_taken' | 'room_not_found' | 'room_full' | 'bad_seats' | 'too_many_rooms';
    };

export function isOpen<S extends OpenState>(socket: S | null | undefined): socket is S {
  return socket !== null && socket !== undefined && socket.readyState === OPEN;
}

/** Assentos ocupados por um socket vivo. */
export function occupied<S extends OpenState>(room: Room<S>): number {
  return room.seats.reduce((total, socket) => total + (isOpen(socket) ? 1 : 0), 0);
}

export function presentSeats<S extends OpenState>(room: Room<S>): Seat[] {
  const seats: Seat[] = [];
  room.seats.forEach((socket, seat) => {
    if (isOpen(socket)) seats.push(seat);
  });
  return seats;
}

/** Os outros sockets vivos da sala. Substituiu "o outro lado". */
export function peersOf<S extends OpenState>(room: Room<S>, seat: Seat): S[] {
  const peers: S[] = [];
  room.seats.forEach((socket, index) => {
    if (index !== seat && isOpen(socket)) peers.push(socket);
  });
  return peers;
}

export class RoomRegistry<S extends OpenState> {
  private readonly rooms = new Map<string, Room<S>>();

  constructor(
    private readonly graceMs: number,
    private readonly maxAgeMs: number,
    /**
     * Teto de salas simultâneas.
     *
     * Abrir sala é a única coisa que um estranho consegue pedir a este processo
     * sem dar nada em troca, e cada sala fica na memória por até quatro horas
     * (`maxAgeMs`) mesmo depois de esvaziar. Sem teto, um laço de conexões que
     * abre e desliga enche a máquina de 256 MB com salas que ninguém vai usar, e
     * o sintoma para quem está jogando é o processo sendo reiniciado pelo Fly no
     * meio da partida.
     *
     * É a mesma defesa que o servidor de Bomberman já tinha
     * (`BomberProtocol.MAX_ROOMS`) e que faltava deste lado. Recusar uma sala
     * nova é ruim; ficar sem servidor para todo mundo é pior, e a recusa tem
     * texto próprio para quem a vê saber que não foi o código dele.
     */
    private readonly roomLimit: number,
    private readonly now: () => number = Date.now,
    private readonly newKey: () => string = () => randomUUID().slice(0, 8)
  ) {}

  get size(): number {
    return this.rooms.size;
  }

  get(code: string): Room<S> | undefined {
    return this.rooms.get(code);
  }

  /**
   * Abre a sala, ou devolve o assento 0 a quem caiu e voltou.
   *
   * O assento só é recusado quando já existe um socket **aberto** nele. Um
   * socket fechado no assento é exatamente o celular que trocou de Wi-Fi para
   * 4G — recusá-lo transformaria toda queda de rede em partida perdida.
   *
   * A capacidade é de quem abriu e não muda depois: ela é o que os outros
   * jogadores estão entrando para jogar, e uma sala que encolhe no meio
   * expulsaria alguém.
   */
  openRoom(
    code: string,
    game: string,
    socket: S,
    listed = false,
    tc = 0,
    capacity = MIN_SEATS,
    host = ''
  ): SeatOutcome<S> {
    if (!isValidSeatCount(capacity)) {
      return { ok: false, reason: 'bad_seats' };
    }
    const existing = this.rooms.get(code);
    if (existing !== undefined) {
      if (isOpen(existing.seats[0])) {
        return { ok: false, reason: 'room_taken' };
      }
      return this.take(existing, 0, socket);
    }
    // A checagem vem **depois** da sala existente: voltar para uma sala que já
    // está na memória não cria nada, e recusar essa volta por causa do teto
    // mataria justamente a reconexão de quem já estava jogando.
    if (this.rooms.size >= this.roomLimit) {
      return { ok: false, reason: 'too_many_rooms' };
    }
    const room: Room<S> = {
      code,
      game,
      listed,
      tc,
      capacity,
      host,
      seats: new Array<S | null>(capacity).fill(null),
      keys: Array.from({ length: capacity }, () => this.newKey()),
      createdAt: this.now(),
      emptySince: null,
    };
    this.rooms.set(code, room);
    return this.take(room, 0, socket);
  }


  /**
   * Salas públicas que ainda cabem alguém: com pelo menos um jogador conectado
   * e um assento livre. Uma sala cheia na lista só renderia um `room_full` do
   * outro lado, e uma sala que esvaziou é uma promessa vazia.
   *
   * Mais nova primeiro: quem acabou de abrir está olhando para a tela agora, e
   * é com quem a partida realmente começa.
   */
  listPublic(limit: number): Room<S>[] {
    const open: Room<S>[] = [];
    for (const room of this.rooms.values()) {
      if (!room.listed) continue;
      const taken = occupied(room);
      if (taken === 0 || taken >= room.capacity) continue;
      open.push(room);
    }
    open.sort((a, b) => b.createdAt - a.createdAt);
    return open.slice(0, limit);
  }

  /**
   * Senta na sala. Com `key`, no assento que aquela chave abriu — é a volta de
   * quem caiu, e ela vale mesmo que o assento pareça ocupado, porque o que está
   * lá é o socket zumbi da conexão anterior. Sem chave, no primeiro livre.
   */
  joinRoom(code: string, socket: S, key = ''): SeatOutcome<S> {
    const room = this.rooms.get(code);
    if (room === undefined) {
      return { ok: false, reason: 'room_not_found' };
    }
    if (key !== '') {
      const seat = room.keys.indexOf(key);
      if (seat >= 0) {
        return this.take(room, seat, socket);
      }
    }
    const free = room.seats.findIndex((seated) => !isOpen(seated));
    if (free < 0) {
      return { ok: false, reason: 'room_full' };
    }
    // Quem senta sem chave é um **novo dono** para o assento, e ganha chave nova.
    //
    // O assento livre pode ser o de alguém que caiu e ainda tem a chave em disco.
    // Sem a troca, os dois abririam a mesma cadeira: o antigo volta e derruba o
    // novo (`take` expulsa o socket que estiver lá, porque é assim que o zumbi da
    // própria conexão sai), o novo reconecta com a mesma chave e derruba de volta.
    // Com a troca, a chave antiga deixa de achar o assento e quem volta com ela
    // senta no próximo livre — ou ouve que a sala encheu.
    room.keys[free] = this.newKey();
    return this.take(room, free, socket);
  }

  private take(room: Room<S>, seat: Seat, socket: S): SeatOutcome<S> {
    const previous = room.seats[seat] ?? null;
    room.seats[seat] = socket;
    room.emptySince = null;
    return {
      ok: true,
      room,
      seat,
      key: room.keys[seat] ?? '',
      evicted: previous !== socket ? previous : null,
    };
  }

  /** Libera o assento. Devolve os outros sockets vivos, para quem quiser avisá-los. */
  release(room: Room<S>, seat: Seat, socket: S): S[] {
    if (room.seats[seat] === socket) {
      room.seats[seat] = null;
    }
    if (occupied(room) === 0) {
      room.emptySince = this.now();
    }
    return peersOf(room, seat);
  }

  /** Salas vencidas, já removidas do registro. O chamador fecha os sockets. */
  sweep(): Room<S>[] {
    const now = this.now();
    const expired: Room<S>[] = [];
    for (const [code, room] of this.rooms) {
      const emptyTooLong = room.emptySince !== null && now - room.emptySince > this.graceMs;
      const tooOld = now - room.createdAt > this.maxAgeMs;
      if (emptyTooLong || tooOld) {
        this.rooms.delete(code);
        expired.push(room);
      }
    }
    return expired;
  }
}
