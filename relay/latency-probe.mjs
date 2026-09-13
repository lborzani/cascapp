import { WebSocket } from 'ws';

/**
 * Mede o atraso do relay do jeito que a partida sente.
 *
 *   node relay/latency-probe.mjs
 *
 * Três medidas, e só a terceira é a que o jogador percebe:
 *
 * 1. HTTP `/healthz` — o servidor está respondendo, e em quanto tempo;
 * 2. abertura do socket — o aperto de mão TLS mais o WebSocket;
 * 3. **lance de ida e volta**: dois clientes numa sala, um manda `msg` e o outro
 *    recebe. É o caminho exato de um lance, e é o número que importa.
 *
 * O `ping` do protocolo **só é atendido dentro de uma sala** — fora dela o
 * servidor responde `not_in_room`. Medir antes de entrar mede a mensagem de erro.
 */

const HTTP = 'https://chess-checkers-relay.fly.dev';
const WS = 'wss://chess-checkers-relay.fly.dev/ws';
const ROUNDS = 15;
const CODE = `PROBE${Math.floor(Math.random() * 900 + 100)}`;

function stats(samples) {
  const sorted = [...samples].sort((a, b) => a - b);
  const sum = sorted.reduce((total, value) => total + value, 0);
  return {
    min: sorted[0],
    median: sorted[Math.floor(sorted.length / 2)],
    p90: sorted[Math.floor(sorted.length * 0.9)],
    max: sorted[sorted.length - 1],
    mean: Math.round(sum / sorted.length),
  };
}

function show(label, s) {
  console.log(
    `${label.padEnd(16)} min ${s.min} | mediana ${s.median} | p90 ${s.p90} | max ${s.max} ms`
  );
}

async function httpTiming() {
  const samples = [];
  for (let i = 0; i < 6; i += 1) {
    const started = Date.now();
    await (await fetch(`${HTTP}/healthz`)).json();
    samples.push(Date.now() - started);
  }
  return stats(samples);
}

function open() {
  const started = Date.now();
  const socket = new WebSocket(WS);
  return new Promise((resolve, reject) => {
    socket.on('open', () => resolve({ socket, elapsed: Date.now() - started }));
    socket.on('error', reject);
  });
}

function waitFor(socket, kind) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`sem "${kind}" em 15 s`)), 15000);
    const onMessage = (raw) => {
      const message = JSON.parse(raw.toString());
      if (message.t !== kind) return;
      clearTimeout(timer);
      socket.off('message', onMessage);
      resolve(message);
    };
    socket.on('message', onMessage);
  });
}

const http = await httpTiming();
show('HTTP /healthz', http);

const host = await open();
const guest = await open();
console.log(`socket aberto    anfitrião ${host.elapsed} ms | convidado ${guest.elapsed} ms`);

host.socket.send(JSON.stringify({ t: 'host', room: CODE, game: 'chess', seats: 2 }));
await waitFor(host.socket, 'joined');
guest.socket.send(JSON.stringify({ t: 'join', room: CODE, key: '' }));
await waitFor(guest.socket, 'joined');

// Ida e volta de um lance: o anfitrião manda, o convidado devolve.
const relay = [];
for (let round = 0; round < ROUNDS; round += 1) {
  const started = Date.now();
  const arrived = waitFor(guest.socket, 'msg');
  host.socket.send(JSON.stringify({ t: 'msg', d: { probe: round } }));
  await arrived;
  relay.push(Date.now() - started);
}
show('lance A->B', stats(relay));

const pings = [];
for (let round = 0; round < ROUNDS; round += 1) {
  const started = Date.now();
  const pong = waitFor(host.socket, 'pong');
  host.socket.send(JSON.stringify({ t: 'ping' }));
  await pong;
  pings.push(Date.now() - started);
}
show('ping/pong', stats(pings));

host.socket.close();
guest.socket.close();
process.exit(0);
