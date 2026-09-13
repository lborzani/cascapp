import { WebSocket } from 'ws';

/**
 * O assento é devolvido quando o convidado sai?
 *
 *   node relay/leave-probe.mjs
 *
 * Reproduz o relato: alguém entra na sala, desiste, e a tela de quem abriu
 * continua contando duas pessoas. O que se pergunta aqui é de quem é a culpa —
 * o servidor não avisa, ou o app não escuta.
 */

const WS = 'wss://chess-checkers-relay.fly.dev/ws';
const CODE = `LEAVE${Math.floor(Math.random() * 900 + 100)}`;

function open() {
  const socket = new WebSocket(WS);
  return new Promise((resolve, reject) => {
    socket.on('open', () => resolve(socket));
    socket.on('error', reject);
  });
}

function waitFor(socket, kind, timeoutMs = 8000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`sem "${kind}"`)), timeoutMs);
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

const host = await open();
host.send(JSON.stringify({ t: 'host', room: CODE, game: 'ludo', seats: 4 }));
const joined = await waitFor(host, 'joined');
console.log(`anfitrião sentou no assento ${joined.seat}; presentes ${JSON.stringify(joined.present)}`);

const guest = await open();
guest.send(JSON.stringify({ t: 'join', room: CODE, key: '' }));
await waitFor(guest, 'joined');
const peer = await waitFor(host, 'peer');
console.log(`anfitrião viu chegar o assento ${peer.seat}`);

// Duas saídas diferentes, porque o app pode fazer qualquer uma das duas.
console.log('--- convidado fecha o socket sem avisar');
const leftByClose = waitFor(host, 'peer_left', 10000).then(
  (message) => `peer_left do assento ${message.seat}`,
  (error) => `NADA: ${error.message}`
);
guest.close();
console.log(await leftByClose);

const second = await open();
second.send(JSON.stringify({ t: 'join', room: CODE, key: '' }));
await waitFor(second, 'joined');
await waitFor(host, 'peer');
console.log('--- convidado manda "leave" antes de fechar');
const leftByMessage = waitFor(host, 'peer_left', 10000).then(
  (message) => `peer_left do assento ${message.seat}`,
  (error) => `NADA: ${error.message}`
);
second.send(JSON.stringify({ t: 'leave' }));
console.log(await leftByMessage);

host.close();
second.close();
process.exit(0);
