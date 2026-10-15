#!/usr/bin/env bash
# Prepara uma release: sobe a versão do preset, commita e cria a tag.
#
#   tools/release.sh 1.21
#
# Não empurra nada. O push da tag é o que dispara `.github/workflows/release.yml`
# — a decisão de publicar —, e continua sendo um comando que alguém digita:
#
#   git push origin HEAD v1.21
#
# Existe porque o bump eram dois campos à mão, e o `version/code` ficou para trás
# (1.20 saiu com code 19). Daqui em diante o code é derivado do nome: maior × 100
# + menor, então 1.21 → 121 e 2.0 → 200. Ele só pode subir — o Android recusa
# instalar por cima um APK de code menor —, e 121 > 19 deixa a transição limpa.
set -euo pipefail

cd "$(dirname "$0")/.."
preset=export_presets.cfg

falha() {
	echo "release: $*" >&2
	exit 1
}

nova="${1:-}"
[[ "$nova" =~ ^([0-9]+)\.([0-9]+)$ ]] || falha "uso: tools/release.sh <maior>.<menor> (ex: 1.21)"
maior=$((10#${BASH_REMATCH[1]}))
menor=$((10#${BASH_REMATCH[2]}))
# Com menor ≥ 100 o code de 1.100 seria o mesmo de 2.0.
((menor < 100)) || falha "o número menor vai até 99; depois de $maior.99 vem $((maior + 1)).0"
code=$((maior * 100 + menor))

atual=$(grep -oP '(?<=^version/name=")[^"]+' "$preset")
code_atual=$(grep -oP '(?<=^version/code=)\d+' "$preset")

# `sort -V` compara por número, como o app: 1.9 < 1.10.
if [ "$nova" = "$atual" ] || [ "$(printf '%s\n%s\n' "$atual" "$nova" | sort -V | tail -1)" != "$nova" ]; then
	falha "$nova não é maior que a versão atual ($atual)"
fi
((code > code_atual)) || falha "o code $code não é maior que o atual ($code_atual)"
git rev-parse -q --verify "refs/tags/v$nova" >/dev/null && falha "a tag v$nova já existe"
# Mudança local no preset iria junto no commit da versão sem ninguém ver.
git diff --quiet HEAD -- "$preset" || falha "$preset tem mudanças não commitadas"

sed -i -E \
	-e "s/^version\/name=\".*\"$/version\/name=\"$nova\"/" \
	-e "s/^version\/code=[0-9]+$/version\/code=$code/" \
	"$preset"

# Só o preset: o que mais estiver no índice fica para o commit de quem o pôs lá.
git commit -q -m "chore: versão $nova (code $code)" -- "$preset"
git tag -a "v$nova" -m "v$nova"

echo "versão $nova (code $code) commitada e marcada como v$nova na branch $(git branch --show-current)."
echo "para publicar: git push origin HEAD v$nova"
