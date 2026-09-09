#!/usr/bin/env bash
# Подготовка и прогон проверок плагинов Afterlight.
#
#   bash tests/run_checks.sh
#
# Скрипт скачивает исходники Helix в tests/.helix (в git не попадают),
# находит LuaJIT и запускает:
#   1. tests/check_helix_contract.py — сверку контракта с исходниками Helix;
#   2. tests/afterlight_music/run.lua — стенд на реальных панелях Helix.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELIX_DIR="$ROOT/tests/.helix"
HELIX_SRC="${HELIX_SRC:-$HELIX_DIR/helix-master}"

if [ ! -d "$HELIX_SRC/gamemode" ]; then
	echo "Скачиваю исходники Helix в $HELIX_DIR ..."
	mkdir -p "$HELIX_DIR"
	curl -fsSL "https://codeload.github.com/NebulousCloud/helix/tar.gz/refs/heads/master" \
		-o "$HELIX_DIR/helix.tar.gz"
	tar -xzf "$HELIX_DIR/helix.tar.gz" -C "$HELIX_DIR"
	rm -f "$HELIX_DIR/helix.tar.gz"
fi

LUAJIT="${LUAJIT:-}"

if [ -z "$LUAJIT" ]; then
	if command -v luajit >/dev/null 2>&1; then
		LUAJIT="luajit"
	elif [ -x "$ROOT/tests/.luajit/src/luajit" ]; then
		LUAJIT="$ROOT/tests/.luajit/src/luajit"
	fi
fi

if [ -z "$LUAJIT" ]; then
	echo "Не найден LuaJIT. Установите его (apt install luajit) или соберите:"
	echo "  git clone --depth 1 -b v2.1 https://github.com/LuaJIT/LuaJIT $ROOT/tests/.luajit"
	echo "  make -C $ROOT/tests/.luajit"
	exit 2
fi

echo
echo "### Контракт с Helix"
HELIX_SRC="$HELIX_SRC" python3 "$ROOT/tests/check_helix_contract.py"

echo
echo "### Стенд Afterlight Music ($LUAJIT)"
(cd "$ROOT/tests/afterlight_music" && HELIX_SRC="$HELIX_SRC" "$LUAJIT" run.lua)
