#!/usr/bin/env python3
"""Генератор клиентской библиотеки описаний уровней VTM-листа.

Читает утверждённый черновик DESCRIPTIONS_DRAFT.md и регистры плагина,
собирает для каждой статистики и дисциплины поуровневые названия и тексты
и пишет libs/cl_descriptions.lua. Файл сгенерирован — править его руками
нельзя; правится черновик, затем повторный прогон этого скрипта.

Запуск:
    python3 tests/gen_vtm_descriptions.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLUGIN = ROOT / "gamemodes" / "darkrp_modded" / "schema" / "plugins" / "afterlight_vtm_stats"
DRAFT = PLUGIN / "DESCRIPTIONS_DRAFT.md"
REGISTRY = PLUGIN / "libs" / "sh_registry.lua"
DISC_REGISTRY = PLUGIN / "libs" / "sh_disciplines_registry.lua"
OUTPUT = PLUGIN / "libs" / "cl_descriptions.lua"

SECTION_RE = re.compile(r"^\*\*[^`]*`([^`]+)`\)\*\*")
LEVEL_RE = re.compile(r"^- (\d) — \*\*(.+?)\*\*:\s*(.+)$")


def capitalize(text: str) -> str:
    return text[0].upper() + text[1:] if text else text


def lua_escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"')


def load_stat_bases() -> dict[str, int]:
    bases: dict[str, int] = {}
    for match in re.finditer(
        r'Register\("([a-z_]+)",\s*"[^"]+",\s*"[a-z]+",\s*"[a-z]+",\s*(\d)\)',
        REGISTRY.read_text(encoding="utf-8"),
    ):
        bases[match.group(1)] = int(match.group(2))
    return bases


def load_discipline_ids() -> list[str]:
    text = DISC_REGISTRY.read_text(encoding="utf-8")
    block = re.search(r"local definitions = \{(.*?)\n\}", text, re.S)
    if not block:
        sys.exit("Не найден блок definitions в реестре дисциплин.")
    return re.findall(r'\{\s*"([a-z_]+)"', block.group(1))


def parse_draft() -> dict[str, list[tuple[int, str, str]]]:
    sections: dict[str, list[tuple[int, str, str]]] = {}
    current = None
    for line in DRAFT.read_text(encoding="utf-8").splitlines():
        header = SECTION_RE.match(line)
        if header:
            current = header.group(1)
            sections.setdefault(current, [])
            continue
        level = LEVEL_RE.match(line)
        if level and current is not None:
            sections[current].append(
                (int(level.group(1)), level.group(2).strip(), capitalize(level.group(3).strip()))
            )
    return sections


def main() -> None:
    stat_bases = load_stat_bases()
    discipline_ids = load_discipline_ids()
    sections = parse_draft()

    expected_ids = list(stat_bases) + discipline_ids
    problems: list[str] = []

    for ident in expected_ids:
        if ident not in sections:
            problems.append(f"секция {ident} отсутствует в черновике")
    for ident in sections:
        if ident not in stat_bases and ident not in discipline_ids:
            problems.append(f"секция {ident} не найдена в регистрах")

    for ident, rows in sections.items():
        # Строка «0 — выдана, но не пробуждена» в черновике безымянная и в
        # тултипы не переносится: точки на листе начинаются с единицы.
        levels = [level for level, _, _ in rows]
        expected = [1, 2, 3, 4, 5]
        if levels != expected:
            problems.append(f"{ident}: уровни {levels}, ожидались {expected}")
        for level, name, text in rows:
            for chunk, where in ((name, "имя"), (text, "текст")):
                if not chunk:
                    problems.append(f"{ident}[{level}]: пустое {where}")
                if "сложность" in chunk:
                    problems.append(f"{ident}[{level}]: в черновике осталась сложность")
                if re.search(r"[A-Za-z]", chunk):
                    problems.append(f"{ident}[{level}]: латиница в {where}: {chunk[:60]}")

    if problems:
        print("ПРОБЛЕМЫ ЧЕРНОВИКА:")
        for problem in problems:
            print(" -", problem)
        sys.exit(1)

    out: list[str] = []
    out.append("-- СГЕНЕРИРОВАНО tests/gen_vtm_descriptions.py из DESCRIPTIONS_DRAFT.md.")
    out.append("-- Не редактировать вручную: правьте черновик и запускайте генератор.")
    out.append("if (!CLIENT) then return end")
    out.append("")
    out.append("ix.vtm = ix.vtm or {}")
    out.append("ix.vtm.descriptions = ix.vtm.descriptions or {}")
    out.append("")

    def emit_table(kind: str, ids: list[str]) -> None:
        out.append(f"ix.vtm.descriptions.{kind} = {{")
        for ident in ids:
            out.append(f"\t{ident} = {{")
            for level, name, text in sections[ident]:
                out.append(f'\t\t[{level}] = {{"{lua_escape(name)}", "{lua_escape(text)}"}},')
            out.append("\t},")
        out.append("}")
        out.append("")

    emit_table("stats", list(stat_bases))
    emit_table("disciplines", discipline_ids)

    out.append("function ix.vtm.descriptions.Get(kind, id, level)")
    out.append("\tlocal pool = kind == \"disciplines\" and ix.vtm.descriptions.disciplines or ix.vtm.descriptions.stats")
    out.append("\tlocal entry = pool[id] and pool[id][level]")
    out.append("\tif (!entry) then return nil end")
    out.append("\treturn entry[1], entry[2]")
    out.append("end")
    out.append("")

    OUTPUT.write_text("\n".join(out), encoding="utf-8")
    print(f"Готово: {OUTPUT.relative_to(ROOT)}")
    print(f"Секций: {len(sections)} (статистики {len(stat_bases)}, дисциплины {len(discipline_ids)})")


if __name__ == "__main__":
    main()
