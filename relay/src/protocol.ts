/**
 * Contrato do relay, num arquivo só.
 *
 * O servidor conhece exatamente estes verbos. Tudo o que o jogo fala viaja
 * opaco dentro de `RelayMessage.d`, que este processo repassa sem abrir — o
 * protocolo do jogo pode mudar sem que o relay precise ser reimplantado.
 *
 * O espelho em GDScript é `net/relay_bridge.gd`; mudar um lado exige mudar o
 * outro.
 *
 * ## Assento é número, não papel
 *
 * Era `'host' | 'guest'`, e isso bastava enquanto todo jogo do catálogo tinha
 * exatamente dois jogadores. O Ludo tem quatro, e um par de nomes não tem como
 * crescer: "guest2" e "guest3" seriam papéis inventados para dizer "o segundo" e
 * "o terceiro", que é o que um índice já diz.
 *
 * Agora a sala nasce com uma **capacidade** (`seats`, escolhida por quem abre) e
 * cada jogador recebe um índice `0..seats-1`. O assento 0 é quem abriu — o que
 * antes se chamava anfitrião —, e continua sendo quem manda o `welcome` do lado
 * do jogo.
 *
 * ## A chave do assento
 *
 * Com dois assentos, "voltar para o seu lugar" era trivial: só havia um livre.
 * Com quatro, quem cai e volta precisa provar **qual** era o seu, senão ocupa o
 * assento de outro que também caiu e as duas partidas ficam trocadas.
 *
 * Por isso o servidor devolve uma `key` no `joined`, e o cliente a manda de
 * volta no `join` da reconexão. Ela não protege a sala — o segredo da sala é o
 * código —, ela só responde "qual assento era o meu".
 */

/** Motivos de recusa. O cliente escolhe a mensagem que mostra a partir daqui. */
export type ErrorReason =
  | 'bad_code'
  | 'bad_seats'
  | 'room_taken'
  | 'room_not_found'
  | 'room_full'
  | 'hello_timeout'
  | 'rate_limited'
  | 'not_in_room';

/** Índice do assento na sala. 0 é quem abriu. */
export type Seat = number;

/**
 * Dois é o mínimo que ainda é uma partida; seis é folga deliberada sobre os
 * quatro do Ludo, para o próximo jogo de mesa não precisar de outro deploy do
 * relay. O teto existe porque `seats` vem do cliente: sem ele, um número
 * absurdo viraria um array absurdo.
 */
export const MIN_SEATS = 2;
export const MAX_SEATS = 6;

export type ClientMessage =
  | {
      t: 'host';
      room: string;
      game: string;
      listed: boolean;
      tc: number;
      seats: number;
      /** Como quem abriu quer ser chamado na lista pública. Vazio é anônimo. */
      name: string;
    }
  /** `key` vazia é a primeira entrada; preenchida, é uma volta ao mesmo assento. */
  | { t: 'join'; room: string; key: string }
  | { t: 'msg'; d: unknown }
  | { t: 'ping' }
  | { t: 'leave' };

/**
 * Uma sala na lista pública. É tudo o que o servidor conta sobre uma partida, e
 * o servidor não guarda nada além disto.
 *
 * `host` é o apelido que quem abriu escolheu no próprio aparelho — não é
 * identidade, não é conta, e nada o verifica. Ele existe porque uma lista de
 * códigos de seis letras não diz com quem se vai jogar, e quem procura partida
 * escolhe pela pessoa antes de escolher pelo ritmo.
 */
export interface RoomSummary {
  code: string;
  game: string;
  /** Apelido de quem abriu, já limpo. Vazio quando ninguém escolheu um. */
  host: string;
  /** Índice do ritmo em `Game.TIME_CONTROLS`, do lado do jogo. */
  tc: number;
  /** Há quantos segundos a sala está aberta. */
  age: number;
  /** Capacidade e ocupação: a lista mostra "2/4" sem precisar adivinhar. */
  seats: number;
  taken: number;
}

export type ServerMessage =
  /**
   * `present` é a sala inteira vista de fora: quem já está sentado, por índice.
   * Com dois assentos isso era um booleano ("o outro chegou?"); com quatro, a
   * pergunta certa passou a ser "quem chegou", e um booleano não responde.
   */
  | {
      t: 'joined';
      seat: Seat;
      game: string;
      seats: number;
      present: Seat[];
      key: string;
    }
  | { t: 'peer'; seat: Seat }
  | { t: 'peer_left'; seat: Seat }
  /** `from` é quem falou. Com mais de dois na sala, "o outro" deixou de existir. */
  | { t: 'msg'; d: unknown; from: Seat }
  | { t: 'pong' }
  | { t: 'error'; reason: ErrorReason; detail: string };

/**
 * Sem `0`/`O`/`1`/`I` na origem (`autoload/pairing.gd`), porque o código é lido
 * de uma tela e digitado à mão. Aqui a faixa é folgada de propósito: validar o
 * alfabeto exato acoplaria o servidor a uma decisão de UI do cliente.
 */
const CODE_PATTERN = /^[A-Z0-9]{4,12}$/;

export function isValidRoomCode(code: string): boolean {
  return CODE_PATTERN.test(code);
}

export function isValidSeatCount(seats: number): boolean {
  return Number.isInteger(seats) && seats >= MIN_SEATS && seats <= MAX_SEATS;
}

/**
 * Mesmo limite do campo de nome do app. Ele existe lá pelo layout do cartão;
 * existe **aqui** por outro motivo, e é por isso que é repetido em vez de
 * confiado ao cliente.
 */
export const MAX_NAME_LENGTH = 18;

/**
 * O apelido, reduzido ao que pode ser desenhado na tela de um estranho.
 *
 * Esta string sai do teclado de uma pessoa e vai para a lista de todas as
 * outras. O cliente já limpa a dele, e isso não conta para nada: quem manda o
 * `host` é um socket qualquer, e um cliente adulterado é a hipótese normal e
 * não a exótica.
 *
 * Some tudo abaixo de U+0020 — quebra de linha inclusive, que esticaria a linha
 * da lista para fora do cartão —, e o resto é cortado no limite. Não há
 * escapamento de HTML porque não há HTML: quem desenha é `draw_string` num
 * `Control`, e ali uma tag é literalmente o texto "<b>".
 */
export function cleanName(value: unknown): string {
  if (typeof value !== 'string') return '';
  let clean = '';
  for (const character of value) {
    const code = character.codePointAt(0) ?? 0;
    if (code >= 0x20 && code !== 0x7f) clean += character;
  }
  return clean.trim().slice(0, MAX_NAME_LENGTH);
}

/**
 * Um frame que chegou pela rede não é `ClientMessage` só porque o TypeScript
 * gostaria que fosse. Esta é a única fronteira do processo, e é onde a validação
 * acontece.
 */
export function parseClientMessage(raw: string): ClientMessage | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (typeof parsed !== 'object' || parsed === null) return null;

  const record = parsed as Record<string, unknown>;
  switch (record.t) {
    case 'host':
      // `listed` é opcional e o padrão é **falso**: uma sala só aparece na lista
      // pública quando quem a abriu pediu isso. Um cliente antigo, que não
      // conhece o campo, abre partida privada — que é o comportamento que ele
      // já esperava.
      //
      // `seats` ausente é dois pelo mesmo raciocínio: é o que todo cliente
      // escrito antes do Ludo quis dizer, e o que ele continua querendo dizer.
      return typeof record.room === 'string'
        ? {
            t: 'host',
            room: record.room,
            game: typeof record.game === 'string' ? record.game : '',
            listed: record.listed === true,
            tc: typeof record.tc === 'number' ? record.tc : 0,
            seats: typeof record.seats === 'number' ? record.seats : MIN_SEATS,
            // Limpo já na fronteira, e não na hora de listar: assim não existe
            // nenhum ponto do processo em que o nome sujo está guardado. Um
            // cliente antigo não manda o campo, e a sala dele fica sem apelido —
            // que é como todas as salas eram até aqui.
            name: cleanName(record.name),
          }
        : null;
    case 'join':
      return typeof record.room === 'string'
        ? {
            t: 'join',
            room: record.room,
            key: typeof record.key === 'string' ? record.key : '',
          }
        : null;
    case 'msg':
      return { t: 'msg', d: record.d };
    case 'ping':
      return { t: 'ping' };
    case 'leave':
      return { t: 'leave' };
    default:
      return null;
  }
}
