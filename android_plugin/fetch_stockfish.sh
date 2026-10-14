#!/usr/bin/env sh
# Baixa o Stockfish oficial para dentro do AAR. Fica fora do git: são ~100 MB
# de binário que se reconstroem de uma versão fixa.
set -eu
VERSION=sf_19
DEST="$(dirname "$0")/plugin/src/main/jniLibs/arm64-v8a"
[ -s "$DEST/libstockfish.so" ] && exit 0
mkdir -p "$DEST"
tmp=$(mktemp -d)
curl -fsSL "https://github.com/official-stockfish/Stockfish/releases/download/$VERSION/stockfish-android-arm64-universal.tar.gz" | tar xz -C "$tmp"
mv "$tmp/stockfish/stockfish-android-arm64-universal" "$DEST/libstockfish.so"
rm -rf "$tmp"
