// Worker de análise do mentor de xadrez.
//
// Pega a revisão pendente mais antiga de `chess_reviews` (status vazio), pede
// ao Stockfish a nota de cada posição da partida e grava `analysis` com
// `status = "done"`, ou `"failed"` quando a partida não serve. Os vereditos
// ficam no app (`GameReview`): aqui só sai o que o motor viu.
//
// Não tem porta aberta: fala com o PocketBase pela rede interna do compose,
// com um superusuário só dele. Os lances vêm de fora (o app do jogador) e vão
// para o stdin do motor, então são validados antes de qualquer `position` —
// uma quebra de linha viraria comando UCI.
//
// Sem dependências: `fetch` e `child_process` do Node.

import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { pathToFileURL } from 'node:url';

// O mesmo formato que a migration aceita (`1760800000_revisoes_xadrez.js`).
export const MOVES = /^[a-h][1-8][a-h][1-8][qrbn]?( [a-h][1-8][a-h][1-8][qrbn]?)*$/;

const env = (name, fallback) => process.env[name] ?? fallback;

export const config = {
  pbUrl: env('PB_URL', 'http://127.0.0.1:8090').replace(/\/+$/, ''),
  email: env('PB_EMAIL', ''),
  password: env('PB_PASSWORD', ''),
  stockfish: env('STOCKFISH', 'stockfish'),
  // Trabalho fixo por posição: mesma resposta em qualquer máquina, o que deixa
  // o cache por posição confiável. O tempo é só teto contra máquina lenta.
  nodes: Number(env('NODES', '200000')),
  movetimeMs: Number(env('MOVETIME_MS', '2000')),
  threads: Number(env('THREADS', '3')),
  hashMb: Number(env('HASH_MB', '128')),
  // ponytail: teto fixo de meios-lances; fila justa por dono se alguém abusar.
  maxPlies: Number(env('MAX_PLIES', '300')),
  idleMs: Number(env('IDLE_MS', '5000')),
};

export const engineLabel = (cfg) => `sf19 nodes=${cfg.nodes}`;

/** Lances validados, já cortados no teto. Lança erro se o texto não serve. */
export function parseMoves(text, maxPlies) {
  if (typeof text !== 'string' || !MOVES.test(text)) {
    throw new Error('lances inválidos');
  }
  return text.split(' ').slice(0, maxPlies);
}

/** O comando `position` da posição depois de `count` lances. */
export function positionCommand(moves, count) {
  return count === 0 ? 'position startpos' : `position startpos moves ${moves.slice(0, count).join(' ')}`;
}

/**
 * Junta uma linha `info` do motor ao que já foi visto. Só a linha principal
 * com nota conta; `currmove`, `string` e outras ficam de fora.
 */
export function readInfo(line, seen) {
  const words = line.trim().split(/\s+/);
  if (words[0] !== 'info') return seen;
  const at = words.indexOf('score');
  if (at < 0) return seen;
  const multipv = words.indexOf('multipv');
  if (multipv >= 0 && words[multipv + 1] !== '1') return seen;
  const next = { ...seen };
  const isMate = words[at + 1] === 'mate';
  next.mate = isMate ? Number(words[at + 2]) : 0;
  const wdl = words.indexOf('wdl');
  if (wdl >= 0) {
    next.wdl = words.slice(wdl + 1, wdl + 4).map(Number);
  } else if (isMate) {
    // Profundidade 0 não traz WDL. `mate 0`: quem tem a vez já levou mate.
    next.wdl = next.mate > 0 ? [1000, 0, 0] : [0, 0, 1000];
  }
  const pv = words.indexOf('pv');
  if (pv >= 0) next.pv = words.slice(pv + 1).join(' ');
  return next;
}

/** O Stockfish num processo à parte, uma busca de cada vez. */
export class Engine {
  constructor(path, args = []) {
    this.proc = spawn(path, args, { stdio: ['pipe', 'pipe', 'ignore'] });
    this.lines = [];
    this.waiting = null;
    this.dead = null;
    const fail = (error) => {
      this.dead = error;
      this.waiting?.reject(error);
      this.waiting = null;
    };
    this.proc.on('error', fail);
    this.proc.on('exit', (code) => fail(new Error(`motor saiu (${code})`)));
    createInterface({ input: this.proc.stdout }).on('line', (line) => {
      if (this.waiting) this.waiting.onLine(line);
    });
  }

  send(command) {
    if (this.dead) throw this.dead;
    this.proc.stdin.write(`${command}\n`);
  }

  /** Lê linhas até `done(line)` dar verdadeiro, ou falha no `timeoutMs`. */
  read(done, onLine = () => {}, timeoutMs = 10000) {
    if (this.dead) return Promise.reject(this.dead);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        // Travado no meio de uma busca não serve para a próxima.
        this.waiting = null;
        this.dead = new Error('motor não respondeu');
        this.proc.kill();
        reject(this.dead);
      }, timeoutMs);
      this.waiting = {
        onLine: (line) => {
          onLine(line);
          if (done(line)) {
            clearTimeout(timer);
            this.waiting = null;
            resolve(line);
          }
        },
        reject: (error) => {
          clearTimeout(timer);
          reject(error);
        },
      };
    });
  }

  async start(cfg) {
    this.send('uci');
    await this.read((line) => line === 'uciok');
    this.send(`setoption name Threads value ${cfg.threads}`);
    this.send(`setoption name Hash value ${cfg.hashMb}`);
    this.send('setoption name UCI_ShowWDL value true');
    this.send('isready');
    await this.read((line) => line === 'readyok');
  }

  /** O que o motor vê na posição depois de `count` lances. */
  async look(moves, count, cfg) {
    this.send(positionCommand(moves, count));
    this.send(`go nodes ${cfg.nodes} movetime ${cfg.movetimeMs}`);
    let seen = { wdl: [0, 1000, 0], mate: 0, pv: '' };
    const last = await this.read(
      (line) => line.startsWith('bestmove'),
      (line) => { seen = readInfo(line, seen); },
      cfg.movetimeMs + 5000,
    );
    const best = last.split(/\s+/)[1] ?? '(none)';
    return { wdl: seen.wdl, mate: seen.mate, best, pv: seen.pv };
  }

  quit() {
    if (!this.dead) this.proc.stdin.write('quit\n');
    this.proc.kill();
  }
}

/** A análise de uma partida: um item por posição, da inicial à última. */
export async function analyse(engine, movesText, cfg) {
  const moves = parseMoves(movesText, cfg.maxPlies);
  engine.send('ucinewgame');
  const out = [];
  for (let count = 0; count <= moves.length; count++) {
    out.push(await engine.look(moves, count, cfg));
  }
  return out;
}

/** O PocketBase visto pelo superusuário do worker. */
export function pocketbase(cfg) {
  let token = '';
  const call = async (method, path, body) => {
    const response = await fetch(cfg.pbUrl + path, {
      method,
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: token } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!response.ok) throw new Error(`${method} ${path}: ${response.status}`);
    return response.json();
  };
  return {
    async signIn() {
      token = '';
      const reply = await call('POST', '/api/collections/_superusers/auth-with-password', {
        identity: cfg.email, password: cfg.password,
      });
      token = reply.token;
    },
    async next() {
      const filter = encodeURIComponent('status = ""');
      const reply = await call('GET', `/api/collections/chess_reviews/records?filter=${filter}&sort=created&perPage=1&skipTotal=1`);
      return reply.items[0] ?? null;
    },
    save(id, fields) {
      return call('PATCH', `/api/collections/chess_reviews/records/${id}`, fields);
    },
  };
}

/**
 * Uma revisão: `done` com a análise, ou `failed` quando os lances não servem
 * ou o motor morre no meio. Devolve o motor a usar na próxima (um novo, se
 * este morreu). Erro do PocketBase sobe: a revisão continua pendente.
 */
export async function handle(review, engine, db, cfg, newEngine) {
  let fields;
  try {
    fields = { status: 'done', analysis: await analyse(engine, review.moves, cfg) };
  } catch (error) {
    console.error(`revisão ${review.id}: ${error.message}`);
    fields = { status: 'failed' };
  }
  await db.save(review.id, { ...fields, engine: engineLabel(cfg) });
  if (!engine.dead) return engine;
  engine.quit();
  const fresh = newEngine();
  await fresh.start(cfg);
  return fresh;
}

/** Esvazia a fila; com `once`, para quando ela acaba. */
export async function run(cfg, { once = false } = {}) {
  const db = pocketbase(cfg);
  await db.signIn();
  const newEngine = () => new Engine(cfg.stockfish);
  let engine = newEngine();
  await engine.start(cfg);
  for (;;) {
    let review;
    try {
      review = await db.next();
    } catch (error) {
      // Token vencido ou PocketBase reiniciando: entra de novo e espera.
      console.error(error.message);
      await new Promise((r) => setTimeout(r, cfg.idleMs));
      await db.signIn().catch((e) => console.error(e.message));
      continue;
    }
    if (!review) {
      if (once) break;
      await new Promise((r) => setTimeout(r, cfg.idleMs));
      continue;
    }
    const started = Date.now();
    engine = await handle(review, engine, db, cfg, newEngine);
    console.log(`revisão ${review.id}: ${review.moves.split(' ').length} meios-lances em ${Date.now() - started} ms`);
  }
  engine.quit();
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  run(config, { once: process.argv.includes('--once') }).catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
