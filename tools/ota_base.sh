#!/usr/bin/env bash
# Imprime a base nativa de uma tag: o APK mais velho que roda o .pck dela.
#
#   tools/ota_base.sh v1.36      # → 1.35
#
# O .pck troca scripts, cenas e assets, e nada além disso. O que mora fora dele
# — o plugin Android, as configurações do projeto (autoloads inclusive), as
# opções do preset e a versão do Godot — só muda instalando um APK. Então o .pck
# de uma versão serve para quem tem o APK da última versão que mexeu em alguma
# dessas coisas, ou de qualquer versão depois dela.
#
# A resposta vem do histórico, comparando cada tag com a anterior: da tag pedida
# para trás, a primeira que mudou a parte nativa é a base. Errar para o lado do
# APK é barato (o jogador baixa 120 MB em vez de 8); errar para o lado do .pck
# abre o app com scripts que o APK não sabe rodar — por isso a lista é larga.
#
# O piso é a versão que trouxe o `Patcher`: APK anterior a ela não sabe carregar
# pacote nenhum. `OTA_FLOOR` existe para o teste olhar tags mais velhas.
set -euo pipefail

cd "$(dirname "$0")/.."

floor="${OTA_FLOOR:-1.35}"
target="${1:?uso: tools/ota_base.sh <tag>}"
target="v${target#v}"

# Fora do .pck. `export_presets.cfg` entra à parte, abaixo.
native=(
	android
	android_plugin
	project.godot
	.github/workflows/release.yml
	.github/actions/godot
	':(glob)**/*.gdextension'
)

# Muda a cada release só no número da versão; qualquer outra linha é nativa.
native_changed() {
	git diff --quiet "$1" "$2" -- "${native[@]}" || return 0
	git diff -U0 "$1" "$2" -- export_presets.cfg |
		grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' |
		grep -qvE '^[+-]version/(name|code)='
}

older() { # a é mais velha que b
	[ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]
}

git rev-parse -q --verify "refs/tags/$target" >/dev/null || {
	echo "ota_base: a tag $target não existe" >&2
	exit 1
}

cur=""
for tag in $(git tag -l 'v*' --sort=-v:refname); do
	if [ -z "$cur" ]; then
		[ "$tag" = "$target" ] && cur="$tag"
		continue
	fi
	version="${cur#v}"
	if ! older "$floor" "$version" || native_changed "$tag" "$cur"; then
		echo "$version"
		exit 0
	fi
	cur="$tag"
done
# Sem tag anterior: a primeira versão é a própria base.
echo "${cur#v}"
