import { cleanName } from './protocol.js';

/**
 * Confere o token de uma conta no PocketBase das contas (`pocketbase/`, no
 * servidor de casa) e devolve o nome dela — ou `null` quando não dá: token
 * inválido, conta apagada, servidor fora do ar ou lento demais.
 *
 * `null` nunca impede ninguém de jogar. O relay só deixa de **confirmar** o
 * nome, e a sala segue com o apelido que cada aparelho escolheu, como sempre
 * foi. É por isso que o tempo é curto: esperar mais não muda o que acontece,
 * só atrasa a confirmação de quem tem conta.
 *
 * Usa o `auth-refresh`, que valida a assinatura e a existência da conta numa
 * chamada só. O token novo que ele devolve é descartado — quem renova é o app.
 */
export type TokenVerifier = (token: string) => Promise<string | null>;

export interface VerifierOptions {
  timeoutMs?: number;
  /** Quanto tempo uma resposta vale. Reconexão no meio da partida não pergunta de novo. */
  cacheMs?: number;
  /** Teto do cache, para um cliente mandando tokens aleatórios não crescer a memória. */
  cacheLimit?: number;
  fetchImpl?: typeof fetch;
}

export function createVerifier(baseUrl: string, options: VerifierOptions = {}): TokenVerifier {
  const timeoutMs = options.timeoutMs ?? 1500;
  const cacheMs = options.cacheMs ?? 10 * 60_000;
  const cacheLimit = options.cacheLimit ?? 5000;
  const fetchImpl = options.fetchImpl ?? fetch;
  const cache = new Map<string, { name: string; until: number }>();
  const url = `${baseUrl.replace(/\/+$/, '')}/api/collections/users/auth-refresh`;

  return async (token: string) => {
    const now = Date.now();
    const hit = cache.get(token);
    if (hit !== undefined && hit.until > now) return hit.name;

    try {
      const response = await fetchImpl(url, {
        method: 'POST',
        headers: { Authorization: token },
        signal: AbortSignal.timeout(timeoutMs),
      });
      if (!response.ok) return null;
      const body = (await response.json()) as { record?: { name?: unknown } };
      const name = cleanName(body.record?.name);
      if (name === '') return null;
      // Só o positivo vai para o cache: uma falha passageira não pode deixar
      // alguém sem nome confirmado pelos próximos dez minutos.
      if (cache.size >= cacheLimit) cache.clear();
      cache.set(token, { name, until: now + cacheMs });
      return name;
    } catch {
      return null;
    }
  };
}
