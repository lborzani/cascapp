// Stockfish de mentira para o `worker.test.mjs`: responde o mínimo do UCI e
// anota cada comando recebido em `FAKE_LOG`. `FAKE_DIE_AT=n` morre na n-ésima
// busca.
import { appendFileSync } from 'node:fs';
import { createInterface } from 'node:readline';

let searches = 0;
createInterface({ input: process.stdin }).on('line', (line) => {
  if (process.env.FAKE_LOG) appendFileSync(process.env.FAKE_LOG, `${JSON.stringify(line)}\n`);
  if (line === 'uci') console.log('id name Fake\nuciok');
  else if (line === 'isready') console.log('readyok');
  else if (line === 'quit') process.exit(0);
  else if (line.startsWith('go')) {
    searches += 1;
    if (Number(process.env.FAKE_DIE_AT) === searches) process.exit(3);
    console.log('info depth 1 currmove e2e4 currmovenumber 1');
    console.log('info depth 10 multipv 1 score cp 31 wdl 500 400 100 nodes 100 pv e2e4 e7e5');
    console.log('bestmove e2e4 ponder e7e5');
  }
});
