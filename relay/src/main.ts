import { createRelay } from './server.js';

const PORT = Number(process.env.PORT ?? 8080);

const relay = createRelay();

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
