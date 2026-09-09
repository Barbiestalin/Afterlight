# Проверки Afterlight Music

Две проверки, обе запускаются одной командой из корня репозитория:

```bash
bash tests/run_checks.sh
```

Скрипт сам скачивает исходники Helix в `tests/.helix/` (в git не попадают) и
ищет LuaJIT (`luajit` из PATH или `tests/.luajit/src/luajit`).

## 1. `check_helix_contract.py` — контракт с исходниками Helix

Сверка по исходникам NebulousCloud/helix, а не по имитации API:

* `ix.gui.menu` — панель `ixMenu` (TAB), её `Remove()` переопределён и ставит
  `bClosing`, поэтому «меню открыто» определяется как `!bClosing`;
* `ix.gui.characterMenu` — панель `ixCharMenu`, `Close()` тоже ставит `bClosing`
  и гасит панель около четырёх секунд;
* `GM:ScoreboardShow` только создаёт `ixMenu`, а `GM:ScoreboardHide` пуст —
  значит, по хуку TAB состояние меню не определить;
* `CharacterLoaded` приходит на клиент, а `OnCharacterDisconnect` существует
  только на сервере;
* `ix.gui.mainMenu` и `ix.gui.tabMenu` в Helix нет — плагины на них не ссылаются;
* меню персонажей и заставка Helix заводят собственные каналы `self.channel`,
  поэтому контроллер их глушит;
* `ixIntro:Remove(bForce)` без флага не убирает панель сразу, а только начинает
  анимацию закрытия;
* из корня папки плагина Helix сам грузит только `sh_plugin.lua`, а папки `libs`
  и `derma` подключает до него — файлы в корне плагин подключает сам через
  `ix.util.Include`, поэтому проверяется, что `cl_plugin.lua`, `cl_volume.lua`
  и `cl_volume_button.lua` подключены.

Отдельно проверяется, что дословные фрагменты из
`afterlight_music/harness/snippets.lua` по-прежнему совпадают с указанными
строками исходников Helix. Если Helix изменится, проверка упадёт и укажет,
какой фрагмент устарел.

## 2. `afterlight_music/run.lua` — стенд на реальных панелях Helix

Запуск вручную:

```bash
cd tests/afterlight_music
HELIX_SRC=/path/to/helix luajit run.lua
FORCE_TRANSLATE=1 HELIX_SRC=/path/to/helix luajit run.lua   # через переводчик GLua
```

Стенд исполняет **настоящие файлы Helix** в мини-модели клиентского GMod:

| файл Helix | что даёт |
| --- | --- |
| `gamemode/core/libs/thirdparty/sh_tween.lua` | библиотека анимаций Helix |
| `gamemode/core/libs/sh_animation.lua` | `Panel:CreateAnimation` |
| `gamemode/core/derma/cl_subpanel.lua` | `ixSubpanel`, `ixSubpanelParent` |
| `gamemode/core/derma/cl_noticebar.lua` | `ixNoticeBar` |
| `gamemode/core/derma/cl_menubutton.lua` | `ixMenuButton`, `ixMenuSelectionButton` |
| `gamemode/core/derma/cl_character.lua` | `ixCharMenuPanel`, `ixCharMenuMain`, `ixCharMenu` |
| `gamemode/core/derma/cl_menu.lua` | `ixMenu` (меню по TAB) |
| `gamemode/core/derma/cl_intro.lua` | `ixIntro` (заставка Helix) |

Плагины `afterlight_intro` и `afterlight_menu_music` загружаются как есть, без
изменений. Методы гейммода (`GM:ScoreboardShow`, `GM:ScoreboardHide`,
`GM:CharacterLoaded`, `GM:LoadIntro`) и net-приёмники меню персонажей взяты
дословно — их сверяет `check_helix_contract.py`.

Модель движка (`harness/env.lua`) повторяет то, от чего зависит поведение:

* `vgui.Create` как в
  `garrysmod/lua/includes/extensions/client/panel/scriptedpanels.lua` — панель
  создаётся от базового класса вверх, `Init` вызывается на каждом уровне
  (именно поэтому `ixSubpanelParent:Init` успевает задать `padding`);
* `Think` и `Paint` вызываются только у видимых панелей, как в VGUI;
* `sound.PlayFile` отвечает асинхронно и возвращает канал с состояниями
  `GMOD_CHANNEL_PLAYING/PAUSED/STOPPED`;
* `cookie`, `timer`, `hook`, `input`, виртуальные часы и покадровый насос.

Покрытые сценарии (142 проверки):

* музыка не стартует, пока не открыт ни один экран;
* заставка: контекст, плавное появление, иконка громкости в панели заставки;
* громкость применяется сразу, cookie пишется после жеста, значения ограничены;
* иконка динамика: положение в правом нижнем углу, клик открывает полосу над
  ней, повторный клик закрывает, колесо на иконке меняет громкость, число дуг
  соответствует уровню (при 0% — перечёркнутый динамик), после простоя полоса
  закрывается сама; отрисовка иконки проверяется по числу вызовов
  `surface.DrawPoly` за один `Paint`;
* скрытая полоса не принимает мышь и не откликается на клики в углу меню;
* перетаскивание и колесо мыши на раскрытой полосе;
* Helix открыл меню персонажей во время заставки — его собственный канал
  заглушён, играет один канал;
* переход заставка → меню персонажей без перезапуска трека и без провала
  громкости, иконка и полоса переезжают;
* выбор персонажа: затухание, канал ставится на паузу и перематывается в начало;
* повторное открытие после полного затухания: трек стартует заново, а переходы
  между экранами (пока звук не затух) продолжаются с того же места;
* TAB: тот же канал снимается с паузы, иконка справа внизу, отпускание TAB
  музыку не рвёт, закрытие TAB — плавное затухание;
* переход TAB → меню персонажей без остановки трека, иконка и полоса уходят
  вместе со своим меню и появляются в новом;
* закрытие меню во время перетаскивания — захват мыши освобождается;
* `lua_refresh`: канал, громкость и единственные иконка с полосой переживают
  перезагрузку, хуки не дублируются;
* зацикливание трека без нового канала;
* заставка Helix не добавляет второй звучащий канал;
* все экраны закрыты — иконка и полоса убраны, состояние контроллера это
  отражает.

### Что стенд не заменяет

Реальный VGUI, отрисовку, поведение `IGModAudioChannel` в движке и звук
проверить можно только в Garry's Mod. Стенд проверяет логику жизненного цикла
и состояние контроллера на настоящих панелях Helix.
