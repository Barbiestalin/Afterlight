-- Стенд плагина Стремительности: исполняет РЕАЛЬНЫЕ файлы плагина
-- (таблица уровней, серверная механика, регистрация способностей, клиент)
-- на заглушках GMod-окружения и сверяет поведение с ТЗ.
local failures = 0
local checks = 0

local function check(condition, label)
	checks = checks + 1
	if (condition) then
		io.write("  ok   " .. label .. "\n")
	else
		failures = failures + 1
		io.write("  FAIL " .. label .. "\n")
	end
end

local function find_root()
	local candidates = {"", "../", "../../", "../../../"}
	for _, prefix in ipairs(candidates) do
		local probe = io.open(prefix .. "tests/afterlight_celerity/run_celerity.lua", "r")
		if (probe) then
			probe:close()
			return prefix
		end
	end
	return ""
end

local root = find_root()
local base = root .. "gamemodes/darkrp_modded/schema/plugins/afterlight_disciplines/plugins/celerity/"

-- ===== Заглушки окружения =====
ix = {}
math.Clamp = function(value, lo, hi) return math.min(math.max(value, lo), hi) end
math.Round = function(value) return math.floor(value + 0.5) end
math.Rand = function(a, b) return a + 0.5 * (b - a) end
function isfunction(value) return type(value) == "function" end
function istable(value) return type(value) == "table" end
function isstring(value) return type(value) == "string" end
function Color(r, g, b, a) return {r = r, g = g, b = b, a = a} end

bit = {band = function(a, b) return a & b end}

DMG_SLASH = 8
DMG_CLUB = 128
DMG_BULLET = 2
DMG_BUCKSHOT = 16
IN_RELOAD = 13

local currentTime = 1000
function CurTime() return currentTime end
function IsValid(entity) return entity ~= nil and entity ~= false and entity.removed ~= true end

hookStore = {}
hook = {Add = function(name, id, fn) hookStore[name] = fn end, Run = function() end}

timer_store = {}
timer = {
	Create = function(name, delay, repeats, callback) timer_store[name] = {at = currentTime + delay, callback = callback} end,
	Remove = function(name) timer_store[name] = nil end,
	Simple = function() end
}
local function stepTimers()
	for name, entry in pairs(timer_store) do
		if (currentTime >= entry.at) then
			timer_store[name] = nil
			entry.callback()
		end
	end
end

netLog = {}
netHandlers = {}
netReadQueue = {}
net = {
	Start = function(name) netLog[#netLog + 1] = {name = name, strings = {}} end,
	WriteString = function(value) local entry = netLog[#netLog]; entry.strings[#entry.strings + 1] = value end,
	Send = function(target) netLog[#netLog].target = target end,
	Receive = function(name, fn) netHandlers[name] = fn end,
	ReadString = function() return table.remove(netReadQueue, 1) end
}

addedFiles = {}
resource = {AddFile = function(path) addedFiles[#addedFiles + 1] = path end}

trails = {}
util = {
	AddNetworkString = function() end,
	SpriteTrail = function(entity, attach, color, additive, startW, endW, life, res, material)
		local trail = {entity = entity, startW = startW, material = material, removed = false}
		trail.Remove = function(self) self.removed = true end
		trails[#trails + 1] = trail
		return trail
	end
}
file = {Exists = function() return false end} -- звуков и материалов ещё нет — код обязан молчать

ix.config = {Get = function(name)
	if (name == "walkSpeed") then return 130 end
	return 260
end}

-- ===== Таблица уровней (реальный файл) =====
PLUGIN = {}
dofile(base .. "libs/sh_celerity_levels.lua")

local spec = {
	{dexterity = 2, duration = 10, vitae = 2, trail = 0, dodge = 0, dodgeBullets = false},
	{dexterity = 2, duration = 15, vitae = 4, trail = 0, dodge = 0, dodgeBullets = false},
	{dexterity = 3, duration = 15, vitae = 5, trail = 1, dodge = 0, dodgeBullets = false},
	{dexterity = 3, duration = 20, vitae = 8, trail = 2, dodge = 3, dodgeBullets = false},
	{dexterity = 4, duration = 20, vitae = 10, trail = 2, dodge = 5, dodgeBullets = true}
}
for level, expected in ipairs(spec) do
	local data = ix.celerity.GetLevelData(level)
	check(data and data.dexterity == expected.dexterity and data.duration == expected.duration
		and data.vitae == expected.vitae and data.trail == expected.trail
		and data.dodge == expected.dodge and data.dodgeBullets == expected.dodgeBullets,
		"уровень " .. level .. ": параметры соответствуют ТЗ")
	if (level > 1) then
		check(ix.celerity.LEVELS[level].walk > ix.celerity.LEVELS[level - 1].walk
			and ix.celerity.LEVELS[level].run > ix.celerity.LEVELS[level - 1].run
			and ix.celerity.LEVELS[level].attack >= ix.celerity.LEVELS[level - 1].attack
			and ix.celerity.LEVELS[level].reload >= ix.celerity.LEVELS[level - 1].reload,
			"уровень " .. level .. ": скорости монотонно растут")
	end
end

-- ===== Серверная механика (реальный файл) =====
dofile(base .. "libs/sv_celerity.lua")

local function make_entity(class, isPlayer)
	local entity = {class = class, player = isPlayer, nw2 = {}, sounds = {}}
	entity.GetClass = function(self) return self.class end
	entity.IsPlayer = function(self) return self.player end
	entity.GetNW2Int = function(self, key, fallback) return self.nw2[key] or fallback end
	entity.GetNW2Float = function(self, key, fallback) return self.nw2[key] or fallback end
	entity.SetNW2Int = function(self, key, value) self.nw2[key] = value end
	entity.SetNW2Float = function(self, key, value) self.nw2[key] = value end
	entity.SteamID64 = function() return "765000000000001" end
	entity.EntIndex = function() return 1 end
	entity.GetCharacter = function(self) return self.character end
	entity.EmitSound = function(self, path) self.sounds[#self.sounds + 1] = path end
	entity.GetWalkSpeed = function(self) return self.walkSpeed or 130 end
	entity.SetWalkSpeed = function(self, value) self.walkSpeed = value end
	entity.GetRunSpeed = function(self) return self.runSpeed or 260 end
	entity.SetRunSpeed = function(self, value) self.runSpeed = value end
	entity.GetActiveWeapon = function(self) return self.weapon end
	entity.Alive = function() return true end
	return entity
end

local function make_weapon(class, melee)
	local weapon = {class = class, nextP = 0, nextS = 0, rate = 1, IsMelee = melee}
	weapon.GetClass = function(self) return self.class end
	weapon.GetNextPrimaryFire = function(self) return self.nextP end
	weapon.SetNextPrimaryFire = function(self, v) self.nextP = v end
	weapon.GetNextSecondaryFire = function(self) return self.nextS end
	weapon.SetNextSecondaryFire = function(self, v) self.nextS = v end
	weapon.SetPlaybackRate = function(self, v) self.rate = v end
	return weapon
end

local client = make_entity("player", true)
local character = {GetPlayer = function() return client end}
client.character = character
player = {GetAll = function() return {client} end}

-- Активация уровня 3: NW2, трейл, персональный звук.
local ok = PLUGIN:ActivateCelerity(client, character, 3)
check(ok == true, "активация уровня 3 успешна")
check(client:GetNW2Int("afterlightCelerityLevel", 0) == 3, "NW2-уровень = 3")
check(math.abs(client:GetNW2Float("afterlightCelerityEnd", 0) - (currentTime + 15)) < 0.01, "длительность 15с")
check(PLUGIN:GetActiveLevel(client) == 3, "GetActiveLevel = 3")
check(PLUGIN:GetCharacterVTMStatBonus(character, "dexterity") == 3, "бонус Ловкости +3 в чарлисте")
check(PLUGIN:GetCharacterVTMStatBonus(character, "strength") == nil, "бонус только к Ловкости")
check(#trails == 1 and trails[1].entity == client and not trails[1].removed, "уровень 3: трейл воздуха создан")
local ownerNet = 0
for _, entry in ipairs(netLog) do
	if (entry.name == "AfterlightCelerityOwnerSound" and entry.target == client) then ownerNet = ownerNet + 1 end
end
check(ownerNet == 1, "звук активации — персональный net владельцу")

-- Скорость выставляется в Think и снимается после окончания.
PLUGIN:Think()
check(client.walkSpeed == math.Round(130 * 1.35) and client.runSpeed == math.Round(260 * 1.5),
	"уровень 3: ходьба и спринт ускорены")

-- Темп ближнего боя: кулдаун кулаков сгорает быстрее.
local hands = make_weapon("ix_hands", true)
client.weapon = hands
hands.nextP = currentTime + 1
currentTime = currentTime + 0.05
PLUGIN:Think()
check(hands.nextP < currentTime + 0.96, "темп ближнего боя: кулдаун тает быстрее реального времени")

-- Анимации: милее размахивает быстрее, огнестрел — только в перезарядке.
local function make_cmd(reload)
	return {keys = {[IN_RELOAD] = reload}, KeyDown = function(self, key) return self.keys[key] == true end}
end
PLUGIN:StartCommand(client, make_cmd(false))
check(hands.rate == 1.5, "анимация ближнего боя ускорена")
local pistol = make_weapon("weapon_pistol", false)
client.weapon = pistol
PLUGIN:StartCommand(client, make_cmd(false))
check(pistol.rate == 1, "огнестрел вне перезарядки в обычном темпе")
PLUGIN:StartCommand(client, make_cmd(true))
check(pistol.rate == 1.5, "перезарядка огнестрела ускорена")

-- Уклонения: 4-й уровень — только ближний бой, 3 раза.
PLUGIN:ActivateCelerity(client, character, 4)
check(client:GetNW2Int("afterlightCelerityDodges", 0) == 3, "уровень 4: 3 уклонения")
check(trails[1].removed == true and #trails == 2 and trails[2].startW > trails[1].startW,
	"уровень 4: старый трейл снят, новый шире")
local function damageInfoOf(dmgType)
	return {
		type = dmgType,
		GetDamageType = function(self) return self.type end,
		GetInflictor = function() return hands end
	}
end
local result = PLUGIN:EntityTakeDamage(client, damageInfoOf(DMG_SLASH))
check(result == 0 and client:GetNW2Int("afterlightCelerityDodges", 0) == 2, "уровень 4: ближний удар уклонён (осталось 2)")
check(PLUGIN:EntityTakeDamage(client, damageInfoOf(DMG_BULLET)) == nil, "уровень 4: пули не уклоняются")
PLUGIN:EntityTakeDamage(client, damageInfoOf(DMG_CLUB))
PLUGIN:EntityTakeDamage(client, damageInfoOf(DMG_SLASH))
check(client:GetNW2Int("afterlightCelerityDodges", 0) == 0, "уклонения потрачены")
check(PLUGIN:EntityTakeDamage(client, damageInfoOf(DMG_SLASH)) == nil, "после 3-х уклонений урон проходит")

-- 5-й уровень: 5 уклонений, включая огнестрел.
PLUGIN:ActivateCelerity(client, character, 5)
check(client:GetNW2Int("afterlightCelerityDodges", 0) == 5, "уровень 5: 5 уклонений")
check(PLUGIN:EntityTakeDamage(client, damageInfoOf(DMG_BULLET)) == 0, "уровень 5: пуля уклонена")

-- Окончание действия: таймер чистит состояние, скорость возвращается.
PLUGIN:ActivateCelerity(client, character, 1)
currentTime = currentTime + 11
stepTimers()
check(client:GetNW2Int("afterlightCelerityLevel", 0) == 0, "после 10с уровень сброшен")
check(trails[#trails].removed == true, "трейл снят по окончании")
PLUGIN:Think()
check(client.walkSpeed == 130 and client.runSpeed == 260, "скорость возвращена к базовой")

-- ===== Регистрация способностей в колесе интерфейса =====
local registered = {}
ix.disciplines = {RegisterPower = function(disc, id, def) registered[id] = def; def.discipline = disc end}
dofile(base .. "sh_plugin.lua")
PLUGIN:InitializedPlugins()
check(registered.celerity_1 ~= nil and registered.celerity_5 ~= nil and registered.celerity_3 ~= nil,
	"пять уровней зарегистрированы в колесе")
check(registered.celerity_4 and registered.celerity_4.GetVitaeCost() == 8, "витэ уровня 4 = 8")
local ctx = {client = client, character = character}
registered.celerity_2.OnActivate(ctx)
check(PLUGIN:GetActiveLevel(client) == 2, "OnActivate колеса включает уровень 2")

-- ===== Клиент: звук активации, амбиент, экранная аура =====
local realTime = 5000
function RealTime() return realTime end
function FrameTime() return 0.05 end
function ScrW() return 1920 end
function ScrH() return 1080 end
function LocalPlayer() return client end

local materialPaths = {}
Material = function(path)
	materialPaths[#materialPaths + 1] = path
	return {path = path, IsError = function() return false end}
end
file.Exists = function() return true end

local fxDraws = 0
surface = {
	SetDrawColor = function() end,
	SetMaterial = function() end,
	DrawTexturedRect = function() fxDraws = fxDraws + 1 end
}

local playedFiles = {}
local loopChannel = nil
sound = {PlayFile = function(path, flags, cb)
	playedFiles[#playedFiles + 1] = path
	if (path:find("celerity.mp3", 1, true)) then
		loopChannel = {
			flags = flags, volume = 0, stopped = false,
			Play = function(self) self.playing = true end,
			SetVolume = function(self, v) self.volume = v end,
			Stop = function(self) self.stopped = true end
		}
		cb(loopChannel)
	else
		cb({
			Play = function() end,
			SetVolume = function() end,
			Stop = function() end
		})
	end
end}

local clientOk = pcall(function()
	dofile(base .. "libs/cl_celerity.lua")
end)
check(clientOk, "клиентская библиотека загружается без ошибок")

-- Звук активации играет только владелец.
netReadQueue = {ix.celerity.SOUND_USE, ix.celerity.SOUND_FALLBACKS.activate}
netHandlers["AfterlightCelerityOwnerSound"]()
check(playedFiles[1] == "sound/" .. ix.celerity.SOUND_USE, "звук активации играет владелец")

-- Аура и амбиент: плавный вход, отрисовка, плавный выход и остановка петли.
local fxHook = hookStore["HUDPaint"]
check(fxHook ~= nil, "аура скорости: HUD-хук зарегистрирован")
client.nw2["afterlightCelerityLevel"] = 2
client.nw2["afterlightCelerityEnd"] = 1e9
for _ = 1, 30 do realTime = realTime + 0.05; currentTime = currentTime + 0.05; fxHook() end
check(ix.celerity.fx.alpha == 1 and fxDraws > 0, "аура: плавно появляется за 1 секунду и рисуется")
check(loopChannel ~= nil and loopChannel.playing, "амбиент: цикл запущен")
for _ = 1, 30 do realTime = realTime + 0.05; currentTime = currentTime + 0.05; fxHook() end
check(loopChannel.volume == ix.celerity.AMBIENT_VOLUME, "амбиент: плавно набрал рабочую громкость")
local foundFx = false
for _, path in ipairs(materialPaths) do
	if (path == "afterlight/disciplines/celerity/celerity_fx_a.png") then foundFx = true end
end
check(foundFx, "аура: оверлей берётся из afterlight/disciplines/celerity")
client.nw2["afterlightCelerityLevel"] = 0
for _ = 1, 25 do realTime = realTime + 0.05; currentTime = currentTime + 0.05; fxHook() end
check(ix.celerity.fx.alpha == 0, "аура: плавно гаснет за 1 секунду")
check(loopChannel.stopped, "амбиент: остановлен после затухания")
local drawsAfter = fxDraws
fxHook()
check(fxDraws == drawsAfter, "аура: после затухания не рисуется")

-- ===== Итог =====
io.write(string.format("Проверок Стремительности: %d, провалено: %d\n", checks, failures))
if (failures > 0) then os.exit(1) end
