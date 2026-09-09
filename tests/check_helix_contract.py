#!/usr/bin/env python3
"""Сверка интеграции плагинов Afterlight с исходниками Helix.

Стенд (tests/afterlight_music/run.lua) исполняет панели Helix в эмуляторе,
а этот скрипт проверяет по исходникам сам контракт: какие панели и хуки
существуют, как они закрываются и что плагины не опираются на то, чего в
Helix нет.

Запуск:
    HELIX_SRC=/path/to/helix python3 tests/check_helix_contract.py
    python3 tests/check_helix_contract.py /path/to/helix

Исходники Helix можно получить так:
    bash tests/fetch_helix.sh
"""

from __future__ import annotations

import os
import re
import sys

SNIPPETS = os.path.join(os.path.dirname(__file__), "afterlight_music", "harness", "snippets.lua")
PLUGINS = os.path.join(
    os.path.dirname(__file__),
    "..",
    "gamemodes",
    "darkrp_modded",
    "schema",
    "plugins",
)


def read(path: str) -> str:
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def strip_comments(text: str) -> str:
    """Убирает комментарии Lua, оставляя строковые литералы нетронутыми."""

    out: list[str] = []
    index = 0
    length = len(text)

    while index < length:
        char = text[index]

        if text.startswith("--[[", index):
            stop = text.find("]]", index + 4)
            index = length if stop < 0 else stop + 2
        elif text.startswith("--", index):
            stop = text.find("\n", index)
            index = length if stop < 0 else stop
        elif char in "\"'":
            quote = char
            out.append(char)
            index += 1

            while index < length:
                if text[index] == "\\":
                    out.append(text[index : index + 2])
                    index += 2
                    continue

                out.append(text[index])

                if text[index] == quote:
                    index += 1
                    break

                index += 1
        else:
            out.append(char)
            index += 1

    return "".join(out)


def normalize(text: str) -> list[str]:
    """Код без отступов, пустых строк и комментариев — сравнение по сути."""

    text = strip_comments(text)

    return [line.strip() for line in text.replace("\r\n", "\n").split("\n") if line.strip()]


class Report:
    def __init__(self) -> None:
        self.passed = 0
        self.failed: list[str] = []

    def ok(self, name: str) -> None:
        self.passed += 1
        print(f"  ok   {name}")

    def fail(self, name: str, detail: str = "") -> None:
        self.failed.append(name)
        print(f"  FAIL {name}" + (f" — {detail}" if detail else ""))

    def check(self, name: str, condition: bool, detail: str = "") -> None:
        if condition:
            self.ok(name)
        else:
            self.fail(name, detail)


def main() -> int:
    root = os.environ.get("HELIX_SRC") or (sys.argv[1] if len(sys.argv) > 1 else "")

    if not root:
        print("Нужен путь к исходникам Helix: HELIX_SRC=... или аргументом.")
        return 2

    root = os.path.abspath(root)

    if not os.path.isdir(os.path.join(root, "gamemode")):
        print(f"В {root} нет папки gamemode — это не исходники Helix.")
        return 2

    report = Report()
    sources: dict[str, str] = {}

    def source(relative: str) -> str:
        if relative not in sources:
            path = os.path.join(root, relative)
            sources[relative] = read(path) if os.path.exists(path) else ""

        return sources[relative]

    print(f"\n== Helix: {root} ==\n")

    print("== панели и их жизненный цикл ==")

    menu = source("gamemode/core/derma/cl_menu.lua")
    report.check(
        "ix.gui.menu — панель ixMenu (TAB)",
        "ix.gui.menu = self" in menu and 'vgui.Register("ixMenu"' in menu,
    )
    report.check(
        "ixMenu:Remove переопределён и ставит bClosing",
        re.search(r"function PANEL:Remove\(\).*?self\.bClosing = true", menu, re.S) is not None,
    )
    report.check(
        "ixMenu закрывается сам, когда TAB отпущен",
        "input.IsKeyDown(KEY_TAB)" in menu and "self:Remove()" in menu,
    )

    character = source("gamemode/core/derma/cl_character.lua")
    report.check(
        "ix.gui.characterMenu — панель ixCharMenu",
        "ix.gui.characterMenu = self" in character and 'vgui.Register("ixCharMenu"' in character,
    )
    report.check(
        "ixCharMenu:Close ставит bClosing и гасит панель анимацией",
        re.search(r"function PANEL:Close\(bFromMenu\)\s*self\.bClosing = true", character)
        is not None,
    )
    report.check(
        "ixCharMenu заводит собственный музыкальный канал",
        "function PANEL:PlayMusic()" in character and "self.channel = channel" in character,
    )
    report.check(
        "меню персонажей играет музыку только без заставки Helix",
        "if (!IsValid(ix.gui.intro)) then" in character,
    )

    intro_panel = source("gamemode/core/derma/cl_intro.lua")
    report.check(
        "ixIntro:Remove(bForce) без флага лишь начинает анимацию закрытия",
        re.search(
            r"function PANEL:Remove\(bForce\)\s*if \(bForce\) then\s*BaseClass\.Remove\(self\)",
            intro_panel,
        )
        is not None
        and "self.bClosing = true" in intro_panel,
    )
    report.check(
        "заставка Helix заводит собственный музыкальный канал",
        "self.channel = channel" in intro_panel and "sound/helix/intro.mp3" in intro_panel,
    )

    hooks = source("gamemode/core/hooks/cl_hooks.lua")
    report.check(
        "GM:ScoreboardShow создаёт ixMenu",
        re.search(
            r"function GM:ScoreboardShow\(\)\s*if \(LocalPlayer\(\):GetCharacter\(\)\) then\s*"
            r'vgui\.Create\("ixMenu"\)',
            hooks,
        )
        is not None,
    )
    report.check(
        "GM:ScoreboardHide пуст — состояние меню читается по панели",
        re.search(r"function GM:ScoreboardHide\(\)\s*end", hooks) is not None,
    )
    report.check(
        "GM:CharacterLoaded закрывает меню персонажей",
        re.search(r"function GM:CharacterLoaded\(\).*?menu:Close\(", hooks, re.S) is not None,
    )

    print("\n== хуки и их области действия ==")

    character_lib = source("gamemode/core/libs/sh_character.lua")
    server_hooks = source("gamemode/core/hooks/sv_hooks.lua")
    report.check(
        "CharacterLoaded приходит на клиент",
        'hook.Run("CharacterLoaded"' in character_lib,
    )
    report.check(
        "OnCharacterDisconnect есть только на сервере",
        'hook.Run("OnCharacterDisconnect"' in server_hooks
        and 'hook.Run("OnCharacterDisconnect"' not in character_lib
        and 'hook.Run("OnCharacterDisconnect"' not in hooks,
    )

    print("\n== сборка плагина ==")

    music_loader = read(os.path.join(PLUGINS, "afterlight_menu_music", "sh_plugin.lua"))

    # Загрузчик Helix исполняет только sh_plugin.lua, поэтому каждый клиентский
    # файл плагина должен быть подключён явно.
    for name in ("cl_plugin.lua", "cl_volume.lua", "cl_volume_button.lua"):
        report.check(
            f"sh_plugin.lua подключает {name}",
            f'ix.util.Include("{name}")' in music_loader,
        )

    print("\n== чего в Helix нет ==")

    everything = ""

    for relative in [
        "gamemode/core/derma/cl_menu.lua",
        "gamemode/core/derma/cl_character.lua",
        "gamemode/core/hooks/cl_hooks.lua",
        "gamemode/core/libs/sh_character.lua",
        "gamemode/core/libs/sh_menu.lua",
    ]:
        everything += source(relative)

    for ghost in ("ix.gui.mainMenu", "ix.gui.tabMenu"):
        report.check(f"{ghost} не используется плагином", ghost not in everything)

    plugins_text = ""

    for folder in ("afterlight_intro", "afterlight_menu_music"):
        for name in sorted(os.listdir(os.path.join(PLUGINS, folder))):
            if name.endswith(".lua"):
                # комментарии не в счёт: в них как раз объяснено, чего в Helix нет
                plugins_text += strip_comments(read(os.path.join(PLUGINS, folder, name)))

    report.check(
        "плагины не ссылаются на несуществующие панели Helix",
        "ix.gui.mainMenu" not in plugins_text and "ix.gui.tabMenu" not in plugins_text,
    )
    report.check(
        "плагины не подписываются на серверный хук",
        'hook.Add("OnCharacterDisconnect"' not in plugins_text,
    )
    report.check(
        "хук предыдущей версии снимается при перезагрузке",
        'hook.Remove("OnCharacterDisconnect", "AfterlightMusicCharacterDisconnect")' in plugins_text,
    )

    print("\n== загрузка плагинов Helix ==")

    plugin_lib = source("gamemode/core/libs/sh_plugin.lua")
    report.check(
        "из папки плагина грузится только sh_plugin.lua",
        'ix.util.Include(isSingleFile and path or path.."/sh_"..variable:lower()..".lua", "shared")'
        in plugin_lib,
    )
    report.check(
        "cl_-файлы плагин подключает сам",
        'ix.util.Include("cl_plugin.lua")' in source("plugins/doors/sh_plugin.lua"),
    )

    util = source("gamemode/core/sh_util.lua")
    report.check(
        'ix.util.Include отправляет cl_-файлы клиенту',
        'fileName:find("cl_")' in util and "AddCSLuaFile(fileName)" in util,
    )

    print("\n== дословные фрагменты стенда ==")

    snippets = read(SNIPPETS)
    snippet_lines = normalize(snippets)
    markers = re.findall(r"-- \[helix\] ([\w/\.]+):(\d+)-(\d+)", snippets)

    report.check("в стенде есть ссылки на исходники Helix", len(markers) > 0)

    for relative, start, end in markers:
        text = source(relative)

        if not text:
            report.fail(f"фрагмент {relative}:{start}-{end}", "файл не найден")
            continue

        expected = normalize(
            "\n".join(text.replace("\r\n", "\n").split("\n")[int(start) - 1 : int(end)])
        )

        found = False

        for index in range(len(snippet_lines) - len(expected) + 1):
            if snippet_lines[index : index + len(expected)] == expected:
                found = True
                break

        report.check(
            f"фрагмент {relative}:{start}-{end} совпадает с Helix",
            found,
            "стенд устарел, обновите snippets.lua",
        )

    print("")
    print(f"Пройдено {report.passed}, провалено {len(report.failed)}")

    if report.failed:
        print("Проваленные проверки:")

        for name in report.failed:
            print(f"  - {name}")

        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
