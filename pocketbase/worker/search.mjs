// Busca de uma posição, na hora, para o desafio "Tentar de novo" e a avaliação
// ao vivo do app. A revisão da partida inteira é do `worker.mjs` (fila); aqui
// é um pedido por vez, com resposta direta.
//
// Fica exposto à internet (Funnel `:8443/cascapp/search`), então nada de fora
// chega ao motor sem passar por aqui:
//   - só conta logada: o token do PocketBase é conferido nele (com cache curto);
//   - limite por conta, e não por IP (atrás do Funnel todo mundo tem o mesmo);
//   - FEN e lances validados antes de virar comando UCI — uma quebra de linha
//     seria um comando a mais, e uma posição sem rei derruba o Stockfish;
//   - nós, tempo, threads e opções só o servidor define;
//   - fila com teto: cheia responde 503, e o app usa o motor dele.
//
// Mesma imagem do worker (Stockfish 19), outro processo: `node search.mjs`.

import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';
import { Engine, MOVES } from './worker.mjs';

const env = (name, fallback) => process.env[name] ?? fallback;

export const config = {
  port: Number(env('PORT', '8093')),
  pbUrl: env('PB_URL', 'http://127.0.0.1:8090').replace(/\/+$/, ''),
  stockfish: env('STOCKFISH', 'stockfish'),
  // Menos que a revisão (200 mil com 3 threads): aqui a resposta é esperada
  // com o jogador olhando, e o processo tem 1 núcleo.
  nodes: Number(env('SEARCH_NODES', '100000')),
  movetimeMs: Number(env('SEARCH_MOVETIME_MS', '1500')),
  threads: 1,
  hashMb: 64,
  perMinute: Number(env('SEARCH_PER_MINUTE', '60')),
  maxPending: Number(env('SEARCH_MAX_PENDING', '8')),
  maxPlies: 600,
  cacheSize: 5000,
};

const FEN = /^([pnbrqkPNBRQK1-8]{1,8}\/){7}[pnbrqkPNBRQK1-8]{1,8} [wb] (-|K?Q?k?q?) (-|[a-h][36]) \d{1,3} \d{1,4}$/;

/** O que há de errado com a FEN, ou `null` se ela pode ir ao motor. */
export function fenProblem(fen) {
  if (typeof fen !== 'string' || !FEN.test(fen) || fen.split(' ')[2] === '') return 'FEN malformada';
  const ranks = fen.split(' ')[0].split('/');
  const width = (rank) => [...rank].reduce((n, c) => n + (/\d/.test(c) ? Number(c) : 1), 0);
  if (ranks.some((rank) => width(rank) !== 8)) return 'fileira sem 8 casas';
  const board = ranks.join('');
  if (board.split('K').length !== 2 || board.split('k').length !== 2) return 'precisa de um rei de cada cor';
  if (/[pP]/.test(ranks[0] + ranks[7])) return 'peão na primeira ou na última fileira';
  // ponytail: não confere se quem não tem a vez está em xeque (pede gerador de
  // lances). O Stockfish pode cair com isso; o motor morto é trocado por outro e
  // o limite por conta segura quem insistir.
  return null;
}

/** `{key, command}` da posição pedida. Lança erro com a mensagem do 400. */
export function positionFor(body, maxPlies) {
  const hasFen = typeof body?.fen === 'string';
  const hasMoves = typeof body?.moves === 'string';
  if (hasFen === hasMoves) throw new Error('mande "fen" ou "moves"');
  if (hasFen) {
    const problem = fenProblem(body.fen);
    if (problem) throw new Error(problem);
    return { key: `fen ${body.fen}`, command: `position fen ${body.fen}` };
  }
  if (body.moves === '') return { key: 'startpos', command: 'position startpos' };
  if (!MOVES.test(body.moves)) throw new Error('lances inválidos');
  if (body.moves.split(' ').length > maxPlies) throw new Error('partida longa demais');
  return { key: `moves ${body.moves}`, command: `position startpos moves ${body.moves}` };
}

/** Quantos pedidos cada conta fez no minuto corrente. */
export function createLimiter(perMinute) {
  let minute = -1;
  let counts = new Map();
  return (id, now = Date.now()) => {
    const current = Math.floor(now / 60000);
    if (current !== minute) {
      minute = current;
      counts = new Map();
    }
    const count = (counts.get(id) ?? 0) + 1;
    counts.set(id, count);
    return count <= perMinute;
  };
}

/** Token do PocketBase → id da conta, ou `null`. Guarda o resultado por `ttlMs`. */
export function createVerifier(pbUrl, { ttlMs = 5 * 60000, fetchImpl = fetch } = {}) {
  const cache = new Map();
  return async (token, now = Date.now()) => {
    if (!token || token.length > 2000) return null;
    const hit = cache.get(token);
    if (hit && hit.until > now) return hit.id;
    let id = null;
    try {
      const reply = await fetchImpl(`${pbUrl}/api/collections/users/auth-refresh`, {
        method: 'POST',
        headers: { Authorization: token },
      });
      if (reply.ok) id = (await reply.json())?.record?.id ?? null;
    } catch {
      return null; // PocketBase fora: recusa, e não guarda.
    }
    if (cache.size > 10000) cache.clear();
    cache.set(token, { id, until: now + ttlMs });
    return id;
  };
}

/**
 * O pedido, sem HTTP: `{token, body}` → `{status, body}`. `engine` é um
 * `Engine` já iniciado; `newEngine` sobe outro quando ele morre.
 */
export function createSearch({ engine, newEngine, verify, limit, cfg }) {
  const cache = new Map();
  let queue = Promise.resolve();
  let pending = 0;

  const run = async (command) => {
    try {
      return await engine.search(command, cfg);
    } finally {
      if (engine.dead) {
        engine.quit();
        engine = newEngine();
        await engine.start(cfg).catch((error) => console.error(`motor novo: ${error.message}`));
      }
    }
  };

  return async ({ token, body }) => {
    const id = await verify(token);
    if (!id) return { status: 401, body: { error: 'conta necessária' } };
    if (!limit(id)) return { status: 429, body: { error: 'devagar' } };
    let position;
    try {
      position = positionFor(body, cfg.maxPlies);
    } catch (error) {
      return { status: 400, body: { error: error.message } };
    }
    const key = `${cfg.nodes}|${position.key}`;
    if (cache.has(key)) return { status: 200, body: cache.get(key) };
    if (pending >= cfg.maxPending) return { status: 503, body: { error: 'ocupado' } };
    pending += 1;
    const turn = queue.then(() => run(position.command));
    queue = turn.catch(() => {});
    try {
      const seen = await turn;
      if (cache.size >= cfg.cacheSize) cache.delete(cache.keys().next().value);
      cache.set(key, seen);
      return { status: 200, body: seen };
    } catch (error) {
      console.error(`busca: ${error.message}`);
      return { status: 500, body: { error: 'motor falhou' } };
    } finally {
      pending -= 1;
    }
  };
}

/** O servidor HTTP em volta: só `POST /search`, corpo JSON de até 8 KB. */
export function serve(handle, port) {
  return createServer((req, res) => {
    const reply = (status, body) => {
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(body));
    };
    if (req.method !== 'POST' || req.url !== '/search') return reply(404, { error: 'não existe' });
    let text = '';
    req.setEncoding('utf8');
    req.on('data', (chunk) => {
      text += chunk;
      if (text.length > 8192) {
        reply(413, { error: 'grande demais' });
        req.destroy();
      }
    });
    req.on('end', async () => {
      if (res.writableEnded) return;
      let body;
      try {
        body = JSON.parse(text);
      } catch {
        return reply(400, { error: 'JSON inválido' });
      }
      const token = String(req.headers.authorization ?? '').replace(/^Bearer /, '');
      const { status, body: out } = await handle({ token, body });
      reply(status, out);
    });
  }).listen(port, '0.0.0.0');
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const newEngine = () => new Engine(config.stockfish);
  const engine = newEngine();
  await engine.start(config);
  const handle = createSearch({
    engine, newEngine, cfg: config,
    verify: createVerifier(config.pbUrl),
    limit: createLimiter(config.perMinute),
  });
  serve(handle, config.port);
  console.log(`busca em :${config.port}, ${config.nodes} nós`);
}
