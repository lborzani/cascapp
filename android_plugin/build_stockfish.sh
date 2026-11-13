#!/usr/bin/env sh
# Compila o Stockfish para dentro do AAR. Fica fora do git: é binário que se
# reconstrói de uma versão fixa.
#
# Stockfish 15.1 **sem a rede NNUE embutida** (`NNUE_EMBEDDING_OFF`): joga com
# a avaliação clássica e o binário tem ~1,5 MB, contra ~98 MB do 19 com a rede.
# O motor do aparelho serve o bot e a reserva sem internet; a análise funda é a
# do servidor (`pocketbase/worker`, SF 19). Medido num Galaxy A16 em 2026-11-12:
# os vereditos da revisão batem com os do servidor. O app liga a avaliação
# clássica com `Use NNUE false` (`core/stockfish.gd`).
#
# Compilado, e não baixado: o binário oficial de Android tem segmentos
# alinhados a 4 KB, e num aparelho com páginas de 16 KB (o padrão dos Android
# novos, e exigência da Play Store) o kernel se recusa a executá-lo. Fora o
# `max-page-size` e a rede, os comandos são os da CI do próprio Stockfish.
set -eu
VERSION=sf_15.1
NDK_VERSION=27.1.12297006
JNI="$(cd "$(dirname "$0")" && pwd)/plugin/src/main/jniLibs"
DEST="$JNI/arm64-v8a"
# A marca fica fora da pasta da ABI, que é o que vai para o AAR. Sem ela, quem
# já tinha o binário do 19 continuaria com ele.
[ -s "$DEST/libstockfish.so" ] && [ "$(cat "$JNI/stockfish.version" 2>/dev/null)" = "$VERSION" ] && exit 0

SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
export PATH="$SDK/ndk/$NDK_VERSION/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
export LDFLAGS="-static -Wno-unused-command-line-argument"

tmp=$(mktemp -d)
curl -fsSL "https://github.com/official-stockfish/Stockfish/archive/refs/tags/$VERSION.tar.gz" | tar xz -C "$tmp"
cd "$tmp"/Stockfish-*/src
make -j"$(nproc)" build ARCH=armv8 COMP=ndk EXTRACXXFLAGS="-DNNUE_EMBEDDING_OFF" EXTRALDFLAGS="-Wl,-z,max-page-size=16384"
make strip ARCH=armv8 COMP=ndk

mkdir -p "$DEST"
mv stockfish "$DEST/libstockfish.so"
echo "$VERSION" > "$JNI/stockfish.version"
rm -rf "$tmp"
