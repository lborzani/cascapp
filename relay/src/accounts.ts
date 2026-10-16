import { cleanName } from './protocol.js';

/**
 * Confere o token de uma conta no PocketBase das contas (`pocketbase/`, no
 * servidor de casa) e devolve o perfil público dela — ou `null` quando não dá:
 * token inválido, conta apagada, servidor fora do ar ou lento demais.
 *
 * `null` nunca impede ninguém de jogar. O relay só deixa de **confirmar** quem
 * está no assento, e a sala segue com o apelido que cada aparelho escolheu, como
 * sempre foi. É por isso que o tempo é curto: esperar mais não muda o que
 * acontece, só atrasa a confirmação de quem tem conta.
 *
 * Usa o `auth-refresh`, que valida a assinatura e a existência da conta numa
 * chamada só. O token novo que ele devolve é descartado — quem renova é o app.
 */
export interface Account {
  /** O id do registro em `users`. É o que o Elo e os amigos usam. */
  id: string;
  name: string;
  /** O nome do arquivo da foto na conta, ou `''` sem foto. */
  avatar: string;
  /** O Elo do xadrez. 0 numa conta de antes do perfil público. */
  elo: number;
}

export type TokenVerifier = (token: string) => Promise<Account | null>;

export interface VerifierOptions {
  timeoutMs?: number;
  /** Quanto tempo uma resposta vale. Reconexão no meio da partida não pergunta de novo. */
  cacheMs?: number;
  /** Teto do cache, para um cliente mandando tokens aleatórios não crescer a memória. */
  cacheLimit?: number;
  fetchImpl?: typeof fetch;
}

/** O formato do id do PocketBase: 15 caracteres, minúsculas e dígitos. */
const ID_PATTERN = /^[a-z0-9]{15}$/;
/** O nome que o PocketBase dá ao arquivo (`avatar_<sufixo>.webp`). Nada de barra. */
const FILE_PATTERN = /^[A-Za-z0-9_.-]{1,100}$/;

/** O que vem do PocketBase vai para os outros aparelhos: só passa o que tem forma conhecida. */
export function toAccount(record: unknown): Account | null {
  if (typeof record !== 'object' || record === null) return null;
  const fields = record as Record<string, unknown>;
  const name = cleanName(fields.name);
  const id = typeof fields.id === 'string' ? fields.id : '';
  if (name === '' || !ID_PATTERN.test(id)) return null;
  const avatar = typeof fields.avatar === 'string' && FILE_PATTERN.test(fields.avatar) ? fields.avatar : '';
  const elo = Number.isInteger(fields.elo_chess) ? Math.max(0, Math.min(4000, fields.elo_chess as number)) : 0;
  return { id, name, avatar, elo };
}

export function createVerifier(baseUrl: string, options: VerifierOptions = {}): TokenVerifier {
  const timeoutMs = options.timeoutMs ?? 1500;
  const cacheMs = options.cacheMs ?? 10 * 60_000;
  const cacheLimit = options.cacheLimit ?? 5000;
  const fetchImpl = options.fetchImpl ?? fetch;
  const cache = new Map<string, { account: Account; until: number }>();
  const url = `${baseUrl.replace(/\/+$/, '')}/api/collections/users/auth-refresh`;

  return async (token: string) => {
    const now = Date.now();
    const hit = cache.get(token);
    if (hit !== undefined && hit.until > now) return hit.account;

    try {
      const response = await fetchImpl(url, {
        method: 'POST',
        headers: { Authorization: token },
        signal: AbortSignal.timeout(timeoutMs),
      });
      if (!response.ok) return null;
      const body = (await response.json()) as { record?: unknown };
      const account = toAccount(body.record);
      if (account === null) return null;
      // Só o positivo vai para o cache: uma falha passageira não pode deixar
      // alguém sem nome confirmado pelos próximos dez minutos.
      if (cache.size >= cacheLimit) cache.clear();
      cache.set(token, { account, until: now + cacheMs });
      return account;
    } catch {
      return null;
    }
  };
}
