-- Стенд плагина Могущества: исполняет РЕАЛЬНЫЕ файлы плагина
-- (таблица уровней, серверная механика, регистрация способностей)
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
		local probe = io.open(prefix .. "tests/afterlight_potence/run_potence.lua", "r")
		if (probe) then
			probe:close()
			return prefix
		end
	end
	return ""
end

local root = find_root()
local base = root .. "gamemodes/darkrp_modded/schema/plugins/afterlight_disciplines/plugins/potence/"

-- ===== Заглушки окружения =====
ix = {}
math.Clamp = function(value, lo, hi) return math.min(math.max(value, lo), hi) end
function isfunction(value) return type(value) == "function" end
function istable(value) return type(value) == "table" end
function isstring(value) return type(value) == "string" end
function isnumber(value) return type(value) == "number" end

-- Минимальный Vector с операциями, которые использует серверный код.
local vectorMeta = {}
vectorMeta.__index = vectorMeta
function vectorMeta:LengthSqr() return self.x * self.x + self.y * self.y + self.z * self.z end
function vectorMeta:Normalize()
	local length = math.sqrt(self:LengthSqr())
	if (length > 0) then self.x, self.y, self.z = self.x / length, self.y / length, self.z / length end
	return self
end
vectorMeta.__mul = function(v, s) return setmetatable({x = v.x * s, y = v.y * s, z = v.z * s}, vectorMeta) end
vectorMeta.__sub = function(a, b) return setmetatable({x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}, vectorMeta) end
function Vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vectorMeta) end

DMG_SLASH = 8
DMG_CLUB = 128
DMG_BULLET = 2

local currentTime = 1000
function CurTime() return currentTime end
function GetConVarNumber() return 600 end
function IsValid(entity) return entity ~= nil and entity ~= false and entity.removed ~= true end

hook = {Add = function() end, Run = function() end}

timer_store = {}
timer = {
	Create = function(name, delay, repeats, callback) timer_store[name] = {at = currentTime + delay, callback = callback} end,
	Remove = function(name) timer_store[name] = nil end,
	Simple = function() end
}

net = {
	Start = function() end, WriteEntity = function() end, WriteVector = function() end,
	WriteUInt = function() end, SendPVS = function() end, Send = function() end
}

addedFiles = {}
resource = {AddFile = function(path) addedFiles[#addedFiles + 1] = path end}

util = {AddNetworkString = function() end}
file = {Exists = function() return false end} -- звуков ещё нет — код обязан молчать

-- ===== Таблица уровней (реальный файл) =====
dofile(base .. "libs/sh_potence_levels.lua")

-- Сверка таблицы уровней с ТЗ.
local spec = {
	{strength = 1, damage = 10, knockbackMeters = 0.5, jumpMeters = 0, duration = 10, vitae = 2, doors = false},
	{strength = 2, damage = 20, knockbackMeters = 1, jumpMeters = 2, duration = 15, vitae = 4, doors = false},
	{strength = 3, damage = 30, knockbackMeters = 2, jumpMeters = 4, duration = 15, vitae = 5, doors = false},
	{strength = 3, damage = 35, knockbackMeters = 4, jumpMeters = 5, duration = 20, vitae = 8, doors = true},
	{strength = 4, damage = 40, knockbackMeters = 6, jumpMeters = 7, duration = 25, vitae = 10, doors = true}
}
for level, expected in ipairs(spec) do
	local data = ix.potence.GetLevelData(level)
	check(data and data.strength == expected.strength and data.damage == expected.damage and
		data.jumpMeters == expected.jumpMeters and data.duration == expected.duration and
		data.vitae == expected.vitae and data.doors == expected.doors,
		"уровень " .. level .. ": параметры соответствуют ТЗ")
	-- Отброс монотонно растёт с метрами из ТЗ.
	if (level > 1) then
		check(ix.potence.LEVELS[level].knockback > ix.potence.LEVELS[level - 1].knockback,
			"уровень " .. level .. ": отброс сильнее предыдущего")
	end
end

local v4 = ix.potence.JumpVelocity(4, 600)
check(math.abs(v4 - math.sqrt(2 * 600 * 4 * 39.37)) < 0.01, "JumpVelocity(4м) = sqrt(2*g*h)")

-- ===== Серверная механика (реальный файл) =====
PLUGIN = {}
dofile(base .. "libs/sv_potence.lua")
dofile(base .. "sh_plugin.lua")

-- Игроки/жертвы/двери.
local function make_entity(class, isPlayer)
	local entity = {class = class, player = isPlayer, nw2 = {}, sounds = {}, fired = {}}
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
	entity.Fire = function(self, input) self.fired[#self.fired + 1] = input end
	entity.GetPos = function(self) return self.pos or Vector(0, 0, 0) end
	entity.GetVelocity = function(self) return self.vel or Vector(0, 0, 0) end
	entity.SetVelocity = function(self, v) self.vel = v end
	entity.GetAimVector = function() return Vector(1, 0, 0) end
	return entity
end

local attacker = make_entity("player", true)
local victim = make_entity("player", true)
victim.pos = Vector(100, 0, 0)
local character = {GetPlayer = function() return attacker end}
attacker.character = character

-- Активация уровня 3: NW2, таймер, бонус Силы.
local ok, reason = PLUGIN:ActivatePotence(attacker, character, 3)
check(ok == true, "активация уровня 3 успешна")
check(reason == nil, "активация без причины отказа")
check(attacker:GetNW2Int("afterlightPotenceLevel", 0) == 3, "NW2-уровень = 3")
check(math.abs(attacker:GetNW2Float("afterlightPotenceEnd", 0) - (currentTime + 15)) < 0.01, "длительность 15с")
check(PLUGIN:GetActiveLevel(attacker) == 3, "GetActiveLevel = 3")
check(PLUGIN:GetCharacterVTMStatBonus(character, "strength") == 3, "бонус Силы +3")
check(PLUGIN:GetCharacterVTMStatBonus(character, "dexterity") == nil, "бонус только к Силе")

-- Повторная активация (уровень 5) сбрасывает таймер.
PLUGIN:ActivatePotence(attacker, character, 5)
check(PLUGIN:GetActiveLevel(attacker) == 5, "повторная активация меняет уровень")
check(math.abs(attacker:GetNW2Float("afterlightPotenceEnd", 0) - (currentTime + 25)) < 0.01, "таймер сброшен на 25с")

-- Урон/отброс/звук: ближний бой (кулаки ix_hands).
local hands = make_entity("ix_hands", false)
local damageInfo = {
	damage = 5, attacker = attacker, inflictor = hands, type = DMG_GENERIC or 0,
	GetDamage = function(self) return self.damage end,
	SetDamage = function(self, value) self.damage = value end,
	GetAttacker = function(self) return self.attacker end,
	GetInflictor = function(self) return self.inflictor end,
	GetDamageType = function(self) return self.type end
}
victim.vel = nil
PLUGIN:EntityTakeDamage(victim, damageInfo)
check(damageInfo.damage == 5 + 40, "урон кулаков +40 (уровень 5)")
check(victim.vel and math.abs(victim.vel.x - 550) < 0.01 and victim.vel.z == 0, "отброс 550 ед/с от атакующего")
check(#attacker.sounds == 0, "звуков нет, пока файлов нет на сервере")

-- Огнестрел не получает бонусов.
local bulletInfo = {damage = 10, attacker = attacker, inflictor = make_entity("weapon_ar2", false), type = DMG_BULLET}
bulletInfo.GetDamage = damageInfo.GetDamage
bulletInfo.SetDamage = damageInfo.SetDamage
bulletInfo.GetAttacker = damageInfo.GetAttacker
bulletInfo.GetInflictor = damageInfo.GetInflictor
bulletInfo.GetDamageType = damageInfo.GetDamageType
PLUGIN:EntityTakeDamage(victim, bulletInfo)
check(bulletInfo.damage == 10, "огнестрел без добавочного урона")

-- Дверь выбивается на уровне 4+.
local door = make_entity("prop_door_rotating", false)
PLUGIN:EntityTakeDamage(door, damageInfo)
check(door.fired[1] == "Unlock" and door.fired[2] == "Open", "дверь: Unlock затем Open")

-- Уровень 2: дверь НЕ выбивается.
PLUGIN:ActivatePotence(attacker, character, 2)
local door2 = make_entity("prop_door_rotating", false)
local info2 = {damage = 5, attacker = attacker, inflictor = hands, type = DMG_CLUB}
info2.GetDamage = damageInfo.GetDamage
info2.SetDamage = damageInfo.SetDamage
info2.GetAttacker = damageInfo.GetAttacker
info2.GetInflictor = damageInfo.GetInflictor
info2.GetDamageType = damageInfo.GetDamageType
PLUGIN:EntityTakeDamage(door2, info2)
check(#door2.fired == 0, "уровень 2: дверь не выбивается")
check(info2.damage == 5 + 20, "урон +20 на уровне 2")

-- Прыжок: уровень 2 → стартовая скорость на 2 метра, без трещины (клиент).
attacker.vel = Vector(0, 0, 0)
PLUGIN:PlayerJump(attacker)
local expect2 = ix.potence.JumpVelocity(2, 600)
check(attacker.vel and math.abs(attacker.vel.z - expect2) < 0.01, "прыжок уровня 2: v=" .. math.floor(expect2))

PLUGIN:ActivatePotence(attacker, character, 3)
attacker.vel = Vector(0, 0, 100)
PLUGIN:PlayerJump(attacker)
local expect3 = ix.potence.JumpVelocity(4, 600)
check(attacker.vel and math.abs(attacker.vel.z - (expect3 - 100)) < 0.01, "прыжок уровня 3: скорость подменяется на 4м")

-- Истечение таймера очищает состояние.
currentTime = currentTime + 30
for _, entry in pairs(timer_store) do entry.callback() end
check(PLUGIN:GetActiveLevel(attacker) == 0, "после истечения таймера уровень 0")
check(PLUGIN:GetCharacterVTMStatBonus(character, "strength") == nil, "после истечения бонуса нет")

-- ===== Регистрация способностей в интерфейсе (реальный sh_plugin.lua) =====
registered = {}
ix.disciplines = {
	RegisterPower = function(disciplineID, powerID, definition)
		registered[#registered + 1] = {discipline = disciplineID, id = powerID, definition = definition}
	end
}
PLUGIN:InitializedPlugins()
check(#registered == 5, "зарегистрировано 5 способностей")
local levelsSeen = {}
for _, entry in ipairs(registered) do
	levelsSeen[entry.definition.level] = true
	check(entry.discipline == "potence", entry.id .. ": дисциплина potence")
	check(entry.definition.GetVitaeCost() == ix.potence.GetLevelData(entry.definition.level).vitae,
		entry.id .. ": стоимость витэ из таблицы")
end
check(levelsSeen[1] and levelsSeen[2] and levelsSeen[3] and levelsSeen[4] and levelsSeen[5],
	"покрыты уровни 1-5")

-- Активация через шлюз: OnActivate способности уровня 1 ставит уровень 1.
currentTime = 5000
local power1 = registered[1].definition
local result = power1.OnActivate({client = attacker, character = character})
check(result == true and PLUGIN:GetActiveLevel(attacker) == 1, "OnActivate уровня 1 работает через шлюз")

-- ===== Синтаксис клиентского файла и регистрации =====
local clientChunk = loadfile(base .. "libs/cl_potence.lua")
check(clientChunk ~= nil, "cl_potence.lua: синтаксис без ошибок")
local shChunk = loadfile(base .. "sh_plugin.lua")
check(shChunk ~= nil, "sh_plugin.lua: синтаксис без ошибок")
local containerChunk = loadfile(root .. "gamemodes/darkrp_modded/schema/plugins/afterlight_disciplines/sh_plugin.lua")
check(containerChunk ~= nil, "контейнер afterlight_disciplines: синтаксис без ошибок")

-- Пути звуков зарезервированы для будущих файлов.
local joined = table.concat(addedFiles, "|")
check(joined:find("afterlight/potence/jump_air.wav", 1, true) ~= nil, "зарезервирован звук прыжка")
check(joined:find("afterlight/potence/hit_light.wav", 1, true) ~= nil, "зарезервирован звук удара 1-2")
check(joined:find("afterlight/potence/hit_heavy.wav", 1, true) ~= nil, "зарезервирован звук удара 3+")

io.write(string.format("Проверок Могущества: %d, провалено: %d\n", checks, failures))
if (failures > 0) then os.exit(1) end
