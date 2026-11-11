#!/bin/bash
# Compila el instalador de Windows (.exe) desde un Mac, sin máquina Windows.
# Necesita: rustup target add x86_64-pc-windows-msvc · cargo install --locked cargo-xwin · brew install nsis llvm lld
set -e
cd "$(dirname "$0")"
. "$HOME/.cargo/env" 2>/dev/null || true
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
# makensis falla con «std::bad_alloc» si no hay un locale UTF-8 (convierte el texto con iconv)
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
npx tauri build --runner cargo-xwin --target x86_64-pc-windows-msvc --bundles nsis
echo "Listo: src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/"
