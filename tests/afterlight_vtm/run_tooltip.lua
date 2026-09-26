-- Стенд тултипа уровней VTM-листа. Исполняет клиентские файлы плагина в
-- LuaJIT на заглушках, повторяющих реальные имена API GMod (wiki.facepunch.com):
-- ловит вызовы несуществующих методов и падения в Init/SetContent/OpenTip.
-- Запуск: luajit tests/afterlight_vtm/run_tooltip.lua (или bash tests/run_checks.sh)

local function find_root()
	local candidates = {"", arg[0]:match("^(.*)tests/") or "", "./", "../", "../../"}
	for _, candidate in ipairs(candidates) do
		local probe = candidate .. "gamemodes/darkrp_modded/schema/plugins/afterlight_vtm_stats/libs/cl_descriptions.lua"
		local handle = io.open(probe, "r")
		if (handle) then
			handle:close()
			return candidate
		end
	end
	io.write("Не найден корень репозитория для стенда тултипа.\n")
	os.exit(1)
end
local root = find_root()
if (root ~= "" and not root:match("/$")) then root = root .. "/" end
local plugin = root .. "gamemodes/darkrp_modded/schema/plugins/afterlight_vtm_stats/"

-- Заглушки GMod-окружения: только методы/глобалы, существующие в GMod.
local function make_label()
	local label = {}
	label.SetFont = function() end
	label.SetTextColor = function() end
	label.SetWrap = function() end
	label.SetAutoStretchVertical = function() end
	label.SizeToContentsY = function() end
	label.SetPos = function() end
	label.SetWide = function() end
	label.SetTall = function(self, h) self._tall = h end
	label.SetText = function(self, text)
		self._text = text
		self._tall = 16 + math.floor(#text / 40) * 14
	end
	label.GetTall = function(self) return self._tall or 16 end
	return label
end

local panel_meta = {}
panel_meta.__index = panel_meta
function panel_meta:Add() return make_label() end
function panel_meta:SetMouseInputEnabled() end
function panel_meta:SetKeyboardInputEnabled() end
function panel_meta:SetZPos() end
function panel_meta:SetWide(w) self._wide = w end
function panel_meta:GetWide() return self._wide or 0 end
function panel_meta:SetTall(h) self._tall = h end
function panel_meta:GetTall() return self._tall or 0 end
function panel_meta:SetPos(x, y) self._x, self._y = x, y end
function panel_meta:InvalidateLayout()
	if (self.PerformLayout) then self.PerformLayout(self) end
end
function panel_meta:Remove() self._removed = true end
function panel_meta:MakePopup() self._popup = true end

local registry = {}
vgui = {
	Register = function(name, class) registry[name] = class end,
	Create = function(name)
		local class = registry[name]
		local meta = {__index = function(_, key) return class[key] or panel_meta[key] end}
		local panel = setmetatable({}, meta)
		class.Init(panel)
		return panel
	end
}
gui = {MousePos = function() return 400, 300 end}
input = {IsMouseDown = function() return false end}
surface = {
	SetDrawColor = function() end,
	DrawRect = function() end,
	DrawOutlinedRect = function() end,
	SetFont = function() end,
	-- Детерминированная метрика: 6px на символ, высота строки 14.
	GetTextSize = function(s) return #s * 6, 14 end
}
function Color(r, g, b, a) return {r = r, g = g, b = b, a = a} end
function ScrW() return 1920 end
function ScrH() return 1080 end
function SysTime() return 0 end
function IsValid(value) return value ~= nil and value ~= false and value._removed ~= true end
math.Clamp = function(value, lo, hi) return math.min(math.max(value, lo), hi) end
MOUSE_LEFT = 107
MOUSE_RIGHT = 108
CLIENT = true
ix = {vtm = {}}

dofile(plugin .. "libs/cl_descriptions.lua")
ix.vtm.stats = {list = setmetatable({}, {__index = function(_, id) return {name = id} end})}
ix.disciplines = {list = setmetatable({}, {__index = function(_, id) return {name = id} end})}
dofile(plugin .. "derma/cl_description_tooltip.lua")

local function make_guard()
	local guard = {_removed = false}
	local scroll = {_removed = false}
	scroll.GetVBar = function() return true end
	scroll.LocalToScreen = function(_, x, y) return x, y end
	scroll.GetWide = function() return 900 end
	scroll.GetTall = function() return 500 end
	scroll.GetParent = function() return nil end
	scroll.LocalToScreen = scroll.LocalToScreen or function(_, x, y) return x, y end
	guard.GetParent = function() return scroll end
	guard.LocalToScreen = guard.LocalToScreen or function(_, x, y) return x, y end
	guard.Add = function(_, class) return vgui.Create(class) end
	guard.ScreenToLocal = function(_, x, y) return x, y end
	guard.GetWide = function() return 1000 end
	guard.GetTall = function() return 800 end
	return guard
end

local failed = 0
local opened = 0
local guard = make_guard()

local function try(kind, id, level)
	local ok, err = pcall(ix.vtm.descriptions.OpenTip, kind, id, level, guard)
	if not ok then
		failed = failed + 1
		io.write("FAIL " .. kind .. " " .. id .. " [" .. level .. "]: " .. tostring(err) .. "\n")
	else
		opened = opened + 1
	end
end

for id, levels in pairs(ix.vtm.descriptions.stats) do
	for level in pairs(levels) do try("stats", id, level) end
end
for id, levels in pairs(ix.vtm.descriptions.disciplines) do
	for level in pairs(levels) do try("disciplines", id, level) end
end

-- Несуществующая запись не должна падать.
try("stats", "no_such_stat", 3)

-- Клик у нижнего края экрана: тултип обязан раскрыться СВЕРХУ от курсора и
-- целиком остаться на экране.
ScrH = function() return 600 end
gui.MousePos = function() return 400, 570 end
ix.vtm.descriptions.OpenTip("disciplines", "dominate", 2, guard)
local tip = ix.vtm.descriptions.lastTip
if (not tip or not tip._y) then
	io.write("FAIL: тултип не создан или не спозиционирован\n")
	os.exit(1)
end
if (not tip._popup) then
	io.write("FAIL: тултип не сделан popup-ом\n")
	os.exit(1)
end
local h = tip:GetTall()
if (tip._y ~= 570 - h - 12) then
	io.write("FAIL: тултип не раскрылся сверху от курсора, y=" .. tostring(tip._y) .. "\n")
	os.exit(1)
end
if (tip._y < 8 or tip._y + h > 600 - 8) then
	io.write("FAIL: тултип выходит за экран, y=" .. tostring(tip._y) .. "\n")
	os.exit(1)
end
io.write("above ok: y=" .. tip._y .. ", tall=" .. h .. "\n")

-- Клик у верхнего края: сверху не помещается — допустимый фолбэк вниз от
-- курсора, зажатый экраном.
local someStat = next(ix.vtm.descriptions.stats)
gui.MousePos = function() return 400, 30 end
ix.vtm.descriptions.OpenTip("stats", someStat, 1, guard)
tip = ix.vtm.descriptions.lastTip
h = tip:GetTall()
local expect = math.min(math.max(30 + 18, 8), 600 - h - 8)
if (tip._y ~= expect) then
	io.write("FAIL: фолбэк вниз у верхнего края неверен, y=" .. tostring(tip._y) .. "\n")
	os.exit(1)
end
io.write("top fallback ok: y=" .. tip._y .. ", tall=" .. h .. "\n")

io.write(string.format("Тултипов открыто: %d, провалено: %d\n", opened, failed))
if (failed > 0) then os.exit(1) end
