#!/usr/bin/env luajit
--[[
	Стенд проверки Afterlight Music.

	Запуск:
	    luajit run.lua <путь к исходникам Helix>
	    HELIX_SRC=/path/to/helix luajit run.lua

	Что исполняется по-настоящему:
	  * gamemode/core/libs/thirdparty/sh_tween.lua  — библиотека анимаций Helix;
	  * gamemode/core/libs/sh_animation.lua         — Panel:CreateAnimation;
	  * gamemode/core/derma/cl_subpanel.lua         — ixSubpanel / ixSubpanelParent;
	  * gamemode/core/derma/cl_noticebar.lua        — ixNoticeBar;
	  * gamemode/core/derma/cl_menubutton.lua       — ixMenuButton и наследники;
	  * gamemode/core/derma/cl_character.lua        — ixCharMenu и его панели;
	  * gamemode/core/derma/cl_menu.lua             — ixMenu (меню по TAB);
	  * gamemode/core/derma/cl_intro.lua            — ixIntro (заставка Helix);
	  * плагины afterlight_intro и afterlight_menu_music без изменений.

	Методы гейммода (GM:ScoreboardShow, GM:CharacterLoaded, net-приёмники меню
	персонажей) взяты дословно из cl_hooks.lua и sh_character.lua — см.
	harness/snippets.lua и check_helix_contract.py.
]]

local root = "./"
local helixRoot = os.getenv("HELIX_SRC") or arg[1]

if (not helixRoot or helixRoot == "") then
	io.write("Нужен путь к исходникам Helix: HELIX_SRC=... luajit run.lua\n")
	os.exit(2)
end

local function normalize(path)
	if (path:sub(-1) ~= "/" and path:sub(-1) ~= "\\") then
		return path .. "/"
	end

	return path
end

helixRoot = normalize(helixRoot)

-- LuaJIT понимает GLua (!, !=, continue) сам; для обычного Lua 5.1 включается
-- переводчик. FORCE_TRANSLATE=1 проверяет переводчик даже на LuaJIT.
local identity = function(source)
	return source
end

local translate = identity

if (jit == nil or os.getenv("FORCE_TRANSLATE") == "1") then
	translate = assert(loadfile(root .. "harness/glua.lua"))()
end

local function loadGLua(path, environment, ...)
	local handle = assert(io.open(path, "rb"))
	local source = handle:read("*a")
	handle:close()

	local chunk = assert(loadstring(translate(source), "@" .. path))

	if (environment) then
		setfenv(chunk, environment)
	end

	return chunk(...)
end

local env = loadGLua(root .. "harness/env.lua")
env.__translate = translate

-- стандартная библиотека остаётся доступной загружаемым скриптам
setmetatable(env, {__index = _G})

loadGLua(root .. "harness/helix.lua", env, env)
loadGLua(root .. "harness/snippets.lua", env, env)

-- настоящие исходники Helix
local helixFiles = {
	"gamemode/core/libs/thirdparty/sh_tween.lua",
	"gamemode/core/libs/sh_animation.lua",
	"gamemode/core/derma/cl_subpanel.lua",
	"gamemode/core/derma/cl_noticebar.lua",
	"gamemode/core/derma/cl_menubutton.lua",
	"gamemode/core/derma/cl_character.lua",
	"gamemode/core/derma/cl_menu.lua",
	"gamemode/core/derma/cl_intro.lua"
}

for _, file in ipairs(helixFiles) do
	env.__loadGLua(helixRoot .. file)
end

env.__registerCharSubpanelStubs()
env.__registerHelixNet()

-- плагины проекта (в том же порядке, в каком их грузит Helix: по алфавиту)
local pluginRoot = normalize(root .. "../../gamemodes/darkrp_modded/schema/plugins/")

local pluginFiles = {
	"afterlight_intro/cl_plugin.lua",
	"afterlight_menu_music/cl_plugin.lua",
	"afterlight_menu_music/cl_volume.lua"
}

local function loadPlugins()
	for _, file in ipairs(pluginFiles) do
		env.__loadGLua(pluginRoot .. file)
	end
end

loadPlugins()

-- =========================================================
-- каркас проверок
-- =========================================================

local passed, failed = 0, 0
local failures = {}

local function check(name, condition, detail)
	if (condition) then
		passed = passed + 1
		print("  ok   " .. name)
	else
		failed = failed + 1
		failures[#failures + 1] = name
		print("  FAIL " .. name .. (detail and (" — " .. tostring(detail)) or ""))
	end
end

local function section(name)
	print("")
	print("== " .. name .. " ==")
end

local MUSIC = env.AfterlightMusic

local function frame(seconds, step)
	env.__advance(seconds or 0.1, step)
end

local function countChannels(state)
	local total = 0

	for _, channel in ipairs(env.__state.channels) do
		if (not state or channel:GetState() == state) then
			total = total + 1
		end
	end

	return total
end

local function countSliders()
	local total = 0

	for _, panel in ipairs(env.__state.panels) do
		if (panel.ClassName == "AfterlightMusicVolume") then
			total = total + 1
		end
	end

	return total
end

local function countHooks(name)
	local total = 0

	for _ in pairs(env.__hooks[name] or {}) do
		total = total + 1
	end

	return total
end

local cookieWrites = 0
local realCookieSet = env.cookie.Set

env.cookie.Set = function(key, value)
	cookieWrites = cookieWrites + 1

	return realCookieSet(key, value)
end

local function inRect(panel)
	local x, y = panel:LocalToScreen(0, 0)

	return x, y, x + panel:GetWide(), y + panel:GetTall()
end

local function pressAt(x, y, panel)
	env.__setCursor(x, y)
	env.__mouseDown(env.MOUSE_LEFT, true)
	panel:OnMousePressed(env.MOUSE_LEFT)
end

local function moveTo(x, y, panel)
	env.__setCursor(x, y)

	if (panel.OnCursorMoved) then
		panel:OnCursorMoved(x, y)
	end
end

local function releaseAt(panel)
	env.__mouseDown(env.MOUSE_LEFT, false)
	panel:OnMouseReleased(env.MOUSE_LEFT)
end

-- =========================================================
-- 1. СОСТОЯНИЕ ПОСЛЕ ЗАГРУЗКИ
-- =========================================================

section("загрузка плагинов")

check("контроллер AfterlightMusic создан", type(MUSIC) == "table")
check("громкость по умолчанию 75%", math.abs(MUSIC.volume - 0.75) < 0.001, MUSIC.volume)
check("канал ещё не создан", MUSIC.channel == nil)
check("ползунка нет, пока нет интерфейса", countSliders() == 0)
check("хук Think один", countHooks("Think") == 1, countHooks("Think"))
check("панель ixCharMenu зарегистрирована", env.__classes.ixCharMenu ~= nil)
check("панель ixMenu зарегистрирована", env.__classes.ixMenu ~= nil)

-- один кадр: заставка стартует по таймеру на 0.05 с и ещё не открылась
frame(0.016)

check("без открытого интерфейса музыка не стартует",
	MUSIC.channel == nil and MUSIC.bWanted == false, "wanted=" .. tostring(MUSIC.bWanted))
check("каналов нет", #env.__state.channels == 0, #env.__state.channels)

-- =========================================================
-- 2. ЗАСТАВКА
-- =========================================================

section("заставка Afterlight")

frame(0.2)

check("интро открылось", env.AfterlightIntro.active == true)
check("панель заставки создана", env.IsValid(env.AfterlightIntro.frame))
check("контекст intro активен", MUSIC:IsContextActive(MUSIC.CONTEXT_INTRO))

frame(0.2)

check("создан ровно один канал", #env.__state.channels == 1, #env.__state.channels)
check("канал играет", MUSIC.channel ~= nil and MUSIC.channel:GetState() == env.GMOD_CHANNEL_PLAYING)
check("огибающая растёт от нуля", MUSIC.envelope > 0 and MUSIC.envelope < 1, MUSIC.envelope)

frame(3)

check("огибающая вышла на 1", math.abs(MUSIC.envelope - 1) < 0.001, MUSIC.envelope)
check("громкость канала равна настройке",
	math.abs(MUSIC.channel:GetVolume() - 0.75) < 0.001, MUSIC.channel:GetVolume())

local introFrame = env.AfterlightIntro.frame
local slider = MUSIC.slider

check("ползунок создан", env.IsValid(slider))
check("ползунок один", countSliders() == 1, countSliders())
check("ползунок живёт в панели заставки", slider ~= nil and slider:GetParent() == introFrame)

if (env.IsValid(slider)) then
	local x, y = slider:GetPos()

	check("ползунок в правом нижнем углу",
		x + slider:GetWide() < introFrame:GetWide() and y + slider:GetTall() < introFrame:GetTall(),
		string.format("%d+%d vs %d, %d+%d vs %d", x, slider:GetWide(), introFrame:GetWide(),
			y, slider:GetTall(), introFrame:GetTall()))
end

-- =========================================================
-- 3. ГРОМКОСТЬ
-- =========================================================

section("громкость")

MUSIC:SetVolume(0.4, true)

check("громкость применена сразу", math.abs(MUSIC.channel:GetVolume() - 0.4) < 0.001,
	MUSIC.channel:GetVolume())
check("cookie во время жеста не пишется", cookieWrites == 0, cookieWrites)

frame(0.6)

check("cookie записан после жеста", cookieWrites == 1, cookieWrites)
check("в cookie то же значение", env.cookie.GetString("afterlight_music_volume") == "0.4",
	env.cookie.GetString("afterlight_music_volume"))

MUSIC:SetVolume(5)
check("значение сверху ограничено", MUSIC.volume == 1, MUSIC.volume)

MUSIC:SetVolume(-3)
check("значение снизу ограничено", MUSIC.volume == 0, MUSIC.volume)
check("при нуле канал не остановлен", MUSIC.channel:GetState() == env.GMOD_CHANNEL_PLAYING)

MUSIC:SetVolume(0.75)
check("громкость возвращена", math.abs(MUSIC.volume - 0.75) < 0.001, MUSIC.volume)

-- =========================================================
-- 4. ПЕРЕТАСКИВАНИЕ И КОЛЕСО
-- =========================================================

section("ползунок: перетаскивание и колесо")

slider = MUSIC.slider
local sliderX, sliderY = slider:LocalToScreen(0, 0)
local inset = math.floor(slider:GetWide() * 0.06)
local trackWidth = slider:GetWide() - inset * 2

local writesBefore = cookieWrites

pressAt(sliderX + inset + trackWidth * 0.3, sliderY + slider:GetTall() * 0.5, slider)

check("захват мыши включён", slider.dragging == true)
check("громкость меняется сразу", math.abs(MUSIC.volume - 0.3) < 0.02, MUSIC.volume)

moveTo(sliderX + inset + trackWidth * 0.6, sliderY + slider:GetTall() * 0.5, slider)
check("перетаскивание обновляет громкость", math.abs(MUSIC.volume - 0.6) < 0.02, MUSIC.volume)
check("cookie во время перетаскивания не пишется", cookieWrites == writesBefore, cookieWrites)

releaseAt(slider)

check("захват мыши снят", slider.dragging == false and slider.m_bMouseCaptured ~= true)
check("cookie записан в конце жеста", cookieWrites == writesBefore + 1, cookieWrites)

local volumeBefore = MUSIC.volume
slider:OnMouseWheeled(1)
check("колесо увеличивает громкость", MUSIC.volume > volumeBefore, MUSIC.volume)
slider:OnMouseWheeled(-1)
check("колесо уменьшает громкость", math.abs(MUSIC.volume - volumeBefore) < 0.001, MUSIC.volume)

-- =========================================================
-- 5. МЕНЮ ПЕРСОНАЖЕЙ ПОЯВЛЯЕТСЯ ВО ВРЕМЯ ЗАСТАВКИ
-- =========================================================

section("меню персонажей во время заставки")

env.__net("ixCharacterMenu", 2, 1001, 1002)
frame(0.1)

local charMenu = env.ix.gui.characterMenu

check("меню персонажей создано Helix", env.IsValid(charMenu))
check("Helix завёл собственный канал", #env.__state.channels == 2, #env.__state.channels)
check("заставка спрятала меню персонажей", charMenu:IsVisible() == false)
check("контекст characterMenu не активен", not MUSIC:IsContextActive(MUSIC.CONTEXT_CHARACTER_MENU))

frame(0.2)

check("собственный канал Helix заглушён",
	charMenu.channel == nil or charMenu.channel:GetState() == env.GMOD_CHANNEL_STOPPED)
check("играет только канал контроллера", countChannels(env.GMOD_CHANNEL_PLAYING) == 1,
	countChannels(env.GMOD_CHANNEL_PLAYING))
check("новых каналов не появилось", #env.__state.channels == 2, #env.__state.channels)

-- =========================================================
-- 6. ЗАСТАВКА -> МЕНЮ ПЕРСОНАЖЕЙ БЕЗ ПЕРЕЗАПУСКА ТРЕКА
-- =========================================================

section("переход заставка -> меню персонажей")

local channelBefore = MUSIC.channel
local timeBefore = MUSIC.channel:GetTime()

env.AfterlightIntro:Close()
frame(0.5)

check("интро затухает, контекст ещё держится", MUSIC:IsContextActive(MUSIC.CONTEXT_INTRO))
check("трек не прерван", MUSIC.channel == channelBefore and MUSIC.channel:GetState() == env.GMOD_CHANNEL_PLAYING)

frame(0.8)

check("интро закрылось", env.AfterlightIntro.active == false)
check("меню персонажей показано", charMenu:IsVisible() == true)
check("контекст characterMenu активен", MUSIC:IsContextActive(MUSIC.CONTEXT_CHARACTER_MENU))
check("канал тот же, без перезапуска", MUSIC.channel == channelBefore)
check("позиция трека продолжилась", MUSIC.channel:GetTime() > timeBefore, MUSIC.channel:GetTime())
check("огибающая не провалилась", MUSIC.envelope > 0.99, MUSIC.envelope)
check("ползунок переехал в меню персонажей", MUSIC.slider ~= nil and MUSIC.slider:GetParent() == charMenu)
check("ползунок по-прежнему один", countSliders() == 1, countSliders())

-- =========================================================
-- 7. ВЫБОР ПЕРСОНАЖА
-- =========================================================

section("выбор персонажа")

env.__player.character = {GetID = function() return 1001 end, GetName = function() return "Тест" end}
env.ix.char.loaded[1001] = env.__player.character

env.__net("ixCharacterLoaded", 1001)
frame(0.2)

check("Helix закрыл меню персонажей", charMenu.bClosing == true)
check("контекст characterMenu снят", not MUSIC:IsContextActive(MUSIC.CONTEXT_CHARACTER_MENU))
check("окно удержания держит звук", MUSIC.bWanted == true)

frame(1.2)

check("затухание началось", MUSIC.envelope < 0.99, MUSIC.envelope)

frame(4)

check("огибающая дошла до нуля", MUSIC.envelope == 0, MUSIC.envelope)
check("канал поставлен на паузу, а не уничтожен",
	MUSIC.channel == channelBefore and MUSIC.channel:GetState() == env.GMOD_CHANNEL_PAUSED,
	MUSIC.channel:GetState())
check("позиция трека сохранена", MUSIC.channel:GetTime() > 1, MUSIC.channel:GetTime())
check("ползунок исчез вместе с меню", countSliders() == 0, countSliders())
check("панель меню персонажей удалена", not env.IsValid(env.ix.gui.characterMenu))

-- =========================================================
-- 8. ИГРОВОЕ МЕНЮ HELIX (TAB)
-- =========================================================

section("игровое меню Helix (TAB)")

local pausedTime = MUSIC.channel:GetTime()

env.hook.Run("ScoreboardShow")
frame(0.2)

local menu = env.ix.gui.menu

check("ixMenu создан", env.IsValid(menu))
check("контекст menu активен", MUSIC:IsContextActive(MUSIC.CONTEXT_MENU))
check("трек продолжился с той же позиции", MUSIC.channel == channelBefore)
check("новый канал не создавался", #env.__state.channels == 2, #env.__state.channels)
check("пауза снята", MUSIC.channel:GetState() == env.GMOD_CHANNEL_PLAYING)
check("позиция не сброшена", MUSIC.channel:GetTime() >= pausedTime, MUSIC.channel:GetTime())
check("ползунок в игровом меню", MUSIC.slider ~= nil and MUSIC.slider:GetParent() == menu)

if (env.IsValid(MUSIC.slider) and env.IsValid(menu)) then
	local x, y = MUSIC.slider:GetPos()
	check("ползунок справа внизу игрового меню",
		x + MUSIC.slider:GetWide() <= menu:GetWide()
			and y + MUSIC.slider:GetTall() <= menu:GetTall()
			and x > menu:GetWide() * 0.8,
		string.format("x=%d y=%d menu=%dx%d", x, y, menu:GetWide(), menu:GetTall()))
end

-- TAB отпущен: в Helix меню остаётся открытым, музыка не должна гаснуть
local envelopeBeforeRelease = MUSIC.envelope

env.hook.Run("ScoreboardHide")
frame(2)

check("после отпускания TAB музыка продолжается",
	MUSIC.bWanted and MUSIC.envelope >= envelopeBeforeRelease,
	"envelope=" .. MUSIC.envelope)

frame(1.5)

check("огибающая вышла на единицу", MUSIC.envelope == 1, MUSIC.envelope)

-- повторное нажатие TAB закрывает меню (ixMenu:Think + OnKeyCodePressed)
env.__keyDown(env.KEY_TAB, true)
frame(0.6)
env.__keyDown(env.KEY_TAB, false)
frame(0.1)

check("ixMenu закрывается", menu.bClosing == true)

frame(1.2)

check("ixMenu удалён", not env.IsValid(env.ix.gui.menu))
check("контекст menu снят", not MUSIC:IsContextActive(MUSIC.CONTEXT_MENU))

frame(4)

check("музыка плавно ушла", MUSIC.envelope == 0, MUSIC.envelope)
check("ползунок удалён вместе с меню", countSliders() == 0, countSliders())

-- =========================================================
-- 9. TAB -> МЕНЮ ПЕРСОНАЖЕЙ
-- =========================================================

section("переход TAB -> меню персонажей")

env.hook.Run("ScoreboardShow")
frame(3)

menu = env.ix.gui.menu
channelBefore = MUSIC.channel

local charactersButton

for _, child in ipairs(menu.buttons:GetChildren()) do
	if (child.GetText and child:GetText() == "CHARACTERS") then
		charactersButton = child
	end
end

check("кнопка characters найдена", charactersButton ~= nil)

local envelopeBefore = MUSIC.envelope
charactersButton:DoClick(charactersButton)
frame(0.3)

check("меню персонажей открыто", env.IsValid(env.ix.gui.characterMenu))
check("ixMenu закрывается", menu.bClosing == true)
check("трек не останавливался", MUSIC.envelope >= envelopeBefore, MUSIC.envelope)
check("канал не пересоздан", MUSIC.channel == channelBefore)
check("ползунок уходит вместе со своим меню", MUSIC.slider ~= nil and MUSIC.slider:GetParent() == menu)

frame(0.2)

check("ползунок гаснет вместе с меню", MUSIC.slider ~= nil and MUSIC.slider.appear < 1,
	MUSIC.slider and MUSIC.slider.appear)

frame(1.2)

check("ixMenu удалён", not env.IsValid(env.ix.gui.menu))
check("ползунок переехал в меню персонажей", MUSIC.slider ~= nil
	and MUSIC.slider:GetParent() == env.ix.gui.characterMenu)
check("ползунок один", countSliders() == 1, countSliders())
check("ползунок снова виден", MUSIC.slider ~= nil and MUSIC.slider.appear > 0.9,
	MUSIC.slider and MUSIC.slider.appear)

-- =========================================================
-- 10. ЗАКРЫТИЕ ИНТЕРФЕЙСА ВО ВРЕМЯ ПЕРЕТАСКИВАНИЯ
-- =========================================================

section("перетаскивание при закрытии интерфейса")

slider = MUSIC.slider
local x, y = slider:LocalToScreen(0, 0)

pressAt(x + slider:GetWide() * 0.5, y + slider:GetTall() * 0.5, slider)
check("захват мыши включён", slider.dragging == true)

env.ix.gui.characterMenu:Close(true)
frame(0.3)

check("захват мыши освобождён", slider.dragging == false)
check("ошибка движка не возникла", #env.__errors == 0, table.concat(env.__errors, "; "))

-- =========================================================
-- 11. LUA_REFRESH
-- =========================================================

section("lua_refresh")

local channelBeforeRefresh = MUSIC.channel
local volumeBeforeRefresh = MUSIC.volume

loadPlugins()
frame(0.2)

check("канал пережил перезагрузку", env.AfterlightMusic.channel == channelBeforeRefresh)
check("громкость сохранилась", math.abs(env.AfterlightMusic.volume - volumeBeforeRefresh) < 0.001,
	env.AfterlightMusic.volume)
check("ползунок не задублировался", countSliders() <= 1, countSliders())
check("хук Think по-прежнему один", countHooks("Think") == 1, countHooks("Think"))
check("старые таймеры предыдущей версии сняты",
	not env.timer.Exists("AfterlightMusicController") and not env.timer.Exists("AfterlightMusicFadeOut"))

MUSIC = env.AfterlightMusic

-- =========================================================
-- 12. ЗАЦИКЛИВАНИЕ ТРЕКА
-- =========================================================

section("зацикливание")

MUSIC:SetContext(MUSIC.CONTEXT_MENU, true)
frame(0.2)

check("музыка снова играет", MUSIC.channel:GetState() == env.GMOD_CHANNEL_PLAYING)

MUSIC.channel:SetTime(MUSIC.channel:GetLength() - 0.1)
frame(0.2)

check("трек начался заново без нового канала", MUSIC.channel:GetTime() < 2, MUSIC.channel:GetTime())
check("играет по-прежнему один канал", countChannels(env.GMOD_CHANNEL_PLAYING) == 1,
	countChannels(env.GMOD_CHANNEL_PLAYING))

-- =========================================================
-- 13. ЗАСТАВКА HELIX НЕ ДАЁТ ВТОРОЙ КАНАЛ
-- =========================================================

section("заставка Helix")

MUSIC:SetContext(MUSIC.CONTEXT_MENU, false)
frame(4)

env.hook.Run("LoadIntro")
frame(2.5)

local helixIntro = env.ix.gui.intro

check("заставка Helix создана", env.IsValid(helixIntro))

if (env.IsValid(helixIntro)) then
	check("канал заставки Helix заглушён",
		helixIntro.channel == nil or helixIntro.channel:GetState() == env.GMOD_CHANNEL_STOPPED)
end

check("играет не больше одного канала", countChannels(env.GMOD_CHANNEL_PLAYING) <= 1,
	countChannels(env.GMOD_CHANNEL_PLAYING))

-- =========================================================
-- ИТОГ
-- =========================================================

print("")
print(string.format("Пройдено %d, провалено %d", passed, failed))

if (failed > 0) then
	print("Проваленные проверки:")

	for _, name in ipairs(failures) do
		print("  - " .. name)
	end

	os.exit(1)
end

os.exit(0)
