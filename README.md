# cascapp

Coleção de jogos de mesa para celular, feita em **Godot 4.7 / GDScript**.

Xadrez, damas, batalha naval, Ludo, Metrópole, Uno, sinuca e boliche. Dá para
jogar contra o bot, no mesmo aparelho ou online: um abre a sala e os outros
entram pelo código, QR Code ou NFC. Tem conta, amigos, loja de visuais, missões
e análise de partidas de xadrez.

## Estrutura

| Pasta | O que tem |
|---|---|
| `core/` | regras e física, sem interface |
| `scenes/`, `ui/` | telas e componentes |
| `autoload/` | estado global (conta, rede, amigos, navegação) |
| `net/`, `relay/` | cliente de rede e o relay (Node/TypeScript) que liga os jogadores |
| `pocketbase/` | contas, amigos, loja e missões (hooks e migrações) |
| `tests/` | testes e sondas de cena, rodados no CI |
| `tools/` | release, deploy do relay e geradores de assets |

Acrescentar um jogo é acrescentar uma entrada em `Game.GAMES`.

## Rodar

Abra a pasta no Godot 4.7 e rode a cena principal.

## Testes

```sh
godot --headless --path . --script res://tests/test_runner.gd
cd relay && npm ci && npm test
```

As outras sondas estão em `.github/workflows/ci.yml`.

## Release

```sh
tools/release.sh 1.73
git push origin HEAD v1.73
```

O push da tag dispara `.github/workflows/release.yml`. As novidades de cada
versão ficam em `CHANGELOG.md`.

A assinatura do APK usa três segredos do repositório no GitHub. O keystore
nunca entra no repositório.

| Segredo | O que é |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | o `.jks` em base64 (`base64 -w0 release-keystore.jks`) |
| `ANDROID_KEYSTORE_ALIAS` | o alias da chave |
| `ANDROID_KEYSTORE_PASSWORD` | a senha do keystore e da chave |
