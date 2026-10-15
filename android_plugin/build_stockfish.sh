#!/usr/bin/env sh
# Compila o Stockfish para dentro do AAR. Fica fora do git: são ~100 MB de
# binário que se reconstroem de uma versão fixa.
#
# Compilado, e não baixado: o binário oficial de Android tem segmentos
# alinhados a 4 KB, e num aparelho com páginas de 16 KB (o padrão dos Android
# novos, e exigência da Play Store) o kernel se recusa a executá-lo. Fora o
# `max-page-size`, os comandos são os da CI do próprio Stockfish.
set -eu
VERSION=sf_19
NDK_VERSION=27.1.12297006
DEST="$(cd "$(dirname "$0")" && pwd)/plugin/src/main/jniLibs/arm64-v8a"
[ -s "$DEST/libstockfish.so" ] && exit 0

SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
export PATH="$SDK/ndk/$NDK_VERSION/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
export LDFLAGS="-static -Wno-unused-command-line-argument"

tmp=$(mktemp -d)
curl -fsSL "https://github.com/official-stockfish/Stockfish/archive/refs/tags/$VERSION.tar.gz" | tar xz -C "$tmp"
cd "$tmp"/Stockfish-*/src
make -j"$(nproc)" build ARCH=arm64-universal COMP=ndk EXTRALDFLAGS="-Wl,-z,max-page-size=16384"
make strip ARCH=arm64-universal COMP=ndk

mkdir -p "$DEST"
mv stockfish "$DEST/libstockfish.so"
rm -rf "$tmp"
