import type { Seat } from './protocol.js';

/**
 * O relay como árbitro do Elo do xadrez.
 *
 * O relay não conhece xadrez e continua não conhecendo: quem diz como a partida
 * acabou são os dois aparelhos, cada um pelas próprias regras. O que o relay
 * sabe e eles não podem forjar é **quem está em cada assento** — a conta
 * conferida pelo token (`accounts.ts`). Então a regra é: os dois contam a mesma
 * coisa, e só aí o resultado vai para o PocketBase, com o segredo que só o relay
 * tem. Um aparelho sozinho, adulterado ou não, nunca muda o Elo de ninguém.
 *
 * A exceção é o abandono: quem fecha o app perdendo não conta nada. Se o
 * assento do outro está vazio há `abandonMs`, o relato de quem ficou vale
 * sozinho.
 */

/** O que cada aparelho conta no fim da partida. */
export interface Report {
  /** O assento que venceu, ou -1 no empate. */
  winner: Seat | -1;
  /** O assento que jogou de brancas. A revanche troca as cores. */
  white: Seat;
  plies: number;
  /** SHA-256 da sequência de lances, em hex. Os dois aparelhos chegam ao mesmo. */
  moves: string;
}

/** Abaixo disto a partida não conta: abrir e abandonar em série não farma Elo. */
export const MIN_PLIES = 4;
const MAX_PLIES = 2000;
const HASH_PATTERN = /^[0-9a-f]{64}$/;

export function parseReport(record: Record<string, unknown>): Report | null {
  const { winner, white, plies, moves } = record;
  if (winner !== -1 && winner !== 0 && winner !== 1) return null;
  if (white !== 0 && white !== 1) return null;
  if (typeof plies !== 'number' || !Number.isInteger(plies) || plies < 0 || plies > MAX_PLIES) return null;
  if (typeof moves !== 'string' || !HASH_PATTERN.test(moves)) return null;
  return { winner, white, plies, moves };
}

export function sameReport(a: Report, b: Report): boolean {
  return a.winner === b.winner && a.white === b.white && a.plies === b.plies && a.moves === b.moves;
}

export type Verdict =
  | { kind: 'rate'; report: Report }
  /** Só um contou e o outro saiu há pouco: perguntar de novo daqui a `ms`. */
  | { kind: 'wait'; ms: number }
  | { kind: 'none' };

/**
 * O que fazer com os relatos de uma mesa de dois.
 *
 * `leftAt[seat]` é quando aquele assento ficou vazio, ou `undefined` se ele está
 * ocupado agora.
 */
export function decide(
  reports: Map<Seat, Report>,
  leftAt: Map<Seat, number>,
  now: number,
  abandonMs: number
): Verdict {
  const first = reports.get(0);
  const second = reports.get(1);
  if (first !== undefined && second !== undefined) {
    return sameReport(first, second) ? { kind: 'rate', report: first } : { kind: 'none' };
  }
  const alone = first ?? second;
  if (alone === undefined) return { kind: 'none' };
  const absent: Seat = first !== undefined ? 1 : 0;
  const since = leftAt.get(absent);
  if (since === undefined) return { kind: 'none' };
  const waited = now - since;
  return waited >= abandonMs ? { kind: 'rate', report: alone } : { kind: 'wait', ms: abandonMs - waited };
}

/** O Elo depois da partida e quanto mudou, por cor. */
export interface Rating {
  elo: number;
  delta: number;
}

export interface RatedGame {
  key: string;
  white: string;
  black: string;
  result: 'white' | 'black' | 'draw';
  plies: number;
}

/** Grava o resultado; `null` se não deu (PocketBase fora, segredo errado). */
export type ResultReporter = (game: RatedGame) => Promise<{ white: Rating; black: Rating } | null>;

export function createReporter(
  baseUrl: string,
  secret: string,
  options: { timeoutMs?: number; fetchImpl?: typeof fetch } = {}
): ResultReporter {
  const timeoutMs = options.timeoutMs ?? 5000;
  const fetchImpl = options.fetchImpl ?? fetch;
  const url = `${baseUrl.replace(/\/+$/, '')}/api/cascapp/chess-result`;
  return async (game) => {
    try {
      const response = await fetchImpl(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Cascapp-Relay': secret },
        body: JSON.stringify(game),
        signal: AbortSignal.timeout(timeoutMs),
      });
      if (!response.ok) return null;
      const body = (await response.json()) as { white?: Partial<Rating>; black?: Partial<Rating> };
      const white = toRating(body.white);
      const black = toRating(body.black);
      return white !== null && black !== null ? { white, black } : null;
    } catch {
      return null;
    }
  };
}

function toRating(value: Partial<Rating> | undefined): Rating | null {
  if (value === undefined || !Number.isInteger(value.elo) || !Number.isInteger(value.delta)) return null;
  return { elo: value.elo as number, delta: value.delta as number };
}
