import { createVerifier } from './accounts.js';
import { createReporter } from './ratings.js';
import { createRelay } from './server.js';

const PORT = Number(process.env.PORT ?? 8080);

// Sem a variável o relay é o de sempre: ninguém tem o nome confirmado.
const POCKETBASE_URL = process.env.POCKETBASE_URL ?? '';

// O segredo que a rota do resultado do PocketBase confere. Sem ele, nenhuma
// partida conta para o Elo — o resto das contas segue igual.
const RELAY_SECRET = process.env.CASCAPP_RELAY_SECRET ?? '';

const relay = createRelay(
  POCKETBASE_URL === ''
    ? {}
    : {
        verifyToken: createVerifier(POCKETBASE_URL),
        ...(RELAY_SECRET === '' ? {} : { reportResult: createReporter(POCKETBASE_URL, RELAY_SECRET) }),
      }
);

void relay.listen(PORT).then((port) => {
  const machine = process.env.FLY_MACHINE_ID ?? 'local';
  // A máquina no log de arranque: se aparecerem duas ao subir uma versão, as
  // salas estão divididas entre elas e metade dos pareamentos vai falhar.
  console.log(`relay ouvindo em 0.0.0.0:${port} (ws em /ws) — máquina ${machine}`);
});

for (const signal of ['SIGTERM', 'SIGINT'] as const) {
  process.on(signal, () => {
    void relay.close().then(() => process.exit(0));
  });
}
