import assert from 'node:assert/strict';
import { WebSocket } from 'ws';

import type { ServerMessage } from './protocol.js';

/** Um aparelho de teste: manda frames e lê o que o relay devolve, na ordem. */
export class Client {
  private readonly inbox: ServerMessage[] = [];
  private waiting: ((message: ServerMessage) => void) | null = null;

  private constructor(private readonly socket: WebSocket) {
    socket.on('message', (raw) => {
      const message = JSON.parse(raw.toString()) as ServerMessage;
      if (this.waiting !== null) {
        const resolve = this.waiting;
        this.waiting = null;
        resolve(message);
      } else {
        this.inbox.push(message);
      }
    });
  }

  static open(url: string): Promise<Client> {
    return new Promise((resolve, reject) => {
      const socket = new WebSocket(url);
      socket.once('open', () => resolve(new Client(socket)));
      socket.once('error', reject);
    });
  }

  send(payload: unknown): void {
    this.socket.send(JSON.stringify(payload));
  }

  next(timeoutMs = 2_000): Promise<ServerMessage> {
    const queued = this.inbox.shift();
    if (queued !== undefined) return Promise.resolve(queued);
    return new Promise((resolve, reject) => {
      // Sem limpar `waiting`, a mensagem que chegasse depois do prazo iria para
      // esta promessa já rejeitada e sumiria — e o `quiet` engoliria a próxima.
      const timer = setTimeout(() => {
        this.waiting = null;
        reject(new Error('nenhuma mensagem chegou'));
      }, timeoutMs);
      this.waiting = (message) => {
        clearTimeout(timer);
        resolve(message);
      };
    });
  }

  /** A próxima mensagem do tipo `t`, pulando as outras. */
  async nextOf<T extends ServerMessage['t']>(t: T, timeoutMs = 2_000): Promise<Extract<ServerMessage, { t: T }>> {
    for (;;) {
      const message = await this.next(timeoutMs);
      if (message.t === t) return message as Extract<ServerMessage, { t: T }>;
    }
  }

  /** Nada chega dentro de `ms`. */
  async quiet(ms = 150): Promise<void> {
    await assert.rejects(this.next(ms));
  }

  close(): void {
    this.socket.close();
  }
}
