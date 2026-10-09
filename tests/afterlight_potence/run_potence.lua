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
function Color(r, g, b, a) return {r = r, g = g, b = b, a = a} end

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
vectorMeta.__add = function(a, b) return setmetatable({x = a.x + b.x, y = a.y + b.y, z = a.z + b.z}, vectorMeta) end
function vectorMeta:Distance(other)
	local dx, dy, dz = self.x - other.x, self.y - other.y, self.z - other.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end
function Vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vectorMeta) end

DMG_SLASH = 8
DMG_CLUB = 128
DMG_BULLET = 2
DMG_FALL = 32

local currentTime = 1000
function CurTime() return currentTime end
function GetConVarNumber() return 600 end
function IsValid(entity) return entity ~= nil and entity ~= false and entity.removed ~= true end

hook = {Add = function(name, id, fn) hookStore[name] = fn end, Run = function() end}
hookStore = {}

timer_store = {}
timer = {
	Create = function(name, delay, repeats, callback) timer_store[name] = {at = currentTime + delay, callback = callback} end,
	Remove = function(name) timer_store[name] = nil end,
	Simple = function() end
}

netLog = {}
netHandlers = {}
netReadQueue = {}
net = {
	Start = function(name) netLog[#netLog + 1] = {name = name, strings = {}} end,
	WriteString = function(value) local entry = netLog[#netLog]; entry.strings[#entry.strings + 1] = value end,
	WriteEntity = function() end, WriteVector = function() end, WriteUInt = function() end,
	SendPVS = function() end,
	Send = function(target) netLog[#netLog].target = target end,
	Receive = function(name, fn) netHandlers[name] = fn end,
	ReadString = function() return table.remove(netReadQueue, 1) end
}

addedFiles = {}
resource = {AddFile = function(path) addedFiles[#addedFiles + 1] = path end}

util = {AddNetworkString = function() end}
file = {Exists = function() return false end} -- звуков ещё нет — код обязан молчать

-- ===== Таблица уровней (реальный файл) =====
PLUGIN = {}
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
	entity.GetShootPos = function(self) return self.pos or Vector(0, 0, 0) end
	return entity
end

local attacker = make_entity("player", true)
local victim = make_entity("player", true)
victim.pos = Vector(100, 0, 0)
local character = {GetPlayer = function() return attacker end}
attacker.character = character
player = {GetAll = function() return {attacker, victim} end}

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
	GetDamageType = function(self) return self.type end,
	IsDamageType = function(self, t) return bit.band(self.type or 0, t) ~= 0 end
}
victim.vel = nil
PLUGIN:EntityTakeDamage(victim, damageInfo)
check(damageInfo.damage == 5 + 40, "урон кулаков +40 (уровень 5)")
check(victim.vel and math.abs(victim.vel.x - 850) < 0.01 and victim.vel.z == 0, "отброс 850 ед/с от атакующего")
local function LastAreaSound()
	for index = #netLog, 1, -1 do
		if (netLog[index].name == "AfterlightPotenceAreaSound") then return netLog[index] end
	end
end
local area = LastAreaSound()
check(area ~= nil and area.strings[1] == ix.potence.SOUND_PUNCH
	and area.strings[2] == ix.potence.SOUND_FALLBACKS.hitHeavy,
	"удар уровня 5: особый звук рассылается в радиусе (фолбэк до добавления файла)")
check(area ~= nil and istable(area.target) and area.target[1] == attacker,
	"удар уровня 5: слушатели в радиусе получают звук")
local ownerSounds = 0
for _, entry in ipairs(netLog) do
	if (entry.name == "AfterlightPotenceOwnerSound" and entry.target == attacker
		and entry.strings[1] == ix.potence.SOUND_USE) then
		ownerSounds = ownerSounds + 1
	end
end
check(ownerSounds == 2, "активация: персональный net-звук только владельцу")
attacker.sounds = {}

-- Огнестрел не получает бонусов.
local bulletInfo = {damage = 10, attacker = attacker, inflictor = make_entity("weapon_ar2", false), type = DMG_BULLET}
bulletInfo.GetDamage = damageInfo.GetDamage
bulletInfo.SetDamage = damageInfo.SetDamage
bulletInfo.GetAttacker = damageInfo.GetAttacker
bulletInfo.GetInflictor = damageInfo.GetInflictor
bulletInfo.GetDamageType = damageInfo.GetDamageType
bulletInfo.IsDamageType = damageInfo.IsDamageType
PLUGIN:EntityTakeDamage(victim, bulletInfo)
check(bulletInfo.damage == 10, "огнестрел без добавочного урона")
check(LastAreaSound() == area, "огнестрел без особого звука")

-- Дверь выбивается на уровне 4+.
local door = make_entity("prop_door_rotating", false)
PLUGIN:EntityTakeDamage(door, damageInfo)
check(door.fired[1] == "unlock" and door.fired[2] == "open", "дверь: unlock затем open")
local areaDoor = LastAreaSound()
check(areaDoor ~= nil and areaDoor ~= area and areaDoor.strings[2] == ix.potence.SOUND_FALLBACKS.hitHeavy,
	"удар по двери: особый звук в радиусе")

-- Уровень 2: дверь НЕ выбивается.
PLUGIN:ActivatePotence(attacker, character, 2)
attacker.sounds = {}
local door2 = make_entity("prop_door_rotating", false)
local info2 = {damage = 5, attacker = attacker, inflictor = hands, type = DMG_CLUB}
info2.GetDamage = damageInfo.GetDamage
info2.SetDamage = damageInfo.SetDamage
info2.GetAttacker = damageInfo.GetAttacker
info2.GetInflictor = damageInfo.GetInflictor
info2.GetDamageType = damageInfo.GetDamageType
info2.IsDamageType = damageInfo.IsDamageType
PLUGIN:EntityTakeDamage(door2, info2)
check(#door2.fired == 0, "уровень 2: дверь не выбивается")
check(info2.damage == 5 + 20, "урон +20 на уровне 2")
local area2 = LastAreaSound()
check(area2 ~= nil and area2 ~= area and area2.strings[2] == ix.potence.SOUND_FALLBACKS.hitLight,
	"удар уровня 2: лёгкий особый звук в радиусе")

-- Прыжок: уровень 1 — без трейла и без подмены скорости.
local trailsCreated = 0
util.SpriteTrail = function() trailsCreated = trailsCreated + 1 return {Remove = function() end} end
PLUGIN:ActivatePotence(attacker, character, 1)
attacker.sounds = {}
attacker.vel = Vector(0, 0, 0)
PLUGIN:OnPlayerJump(attacker)
check(trailsCreated == 0, "прыжок уровня 1: без трейла")
check(attacker.vel.z == 0, "прыжок уровня 1: скорость не подменяется")
check(#attacker.sounds == 0, "прыжок уровня 1: без звука")

-- Прыжок: уровень 2 → стартовая скорость на 2 метра и трейл ряби (сервер).
PLUGIN:ActivatePotence(attacker, character, 2)
attacker.sounds = {}
attacker.vel = Vector(0, 0, 0)
PLUGIN:OnPlayerJump(attacker)
check(trailsCreated == 1, "прыжок уровня 2: трейл создан на сервере")
check(#attacker.sounds == 1 and attacker.sounds[1] == ix.potence.SOUND_FALLBACKS.jump,
	"прыжок уровня 2: колебание воздуха (фолбэк)")
attacker.sounds = {}
local expect2 = ix.potence.JumpVelocity(2, 600)
check(attacker.vel and math.abs(attacker.vel.z - expect2) < 0.01, "прыжок уровня 2: v=" .. math.floor(expect2))

PLUGIN:ActivatePotence(attacker, character, 3)
attacker.sounds = {}
attacker.vel = Vector(0, 0, 100)
PLUGIN:OnPlayerJump(attacker)
local expect3 = ix.potence.JumpVelocity(4, 600)
check(attacker.vel and math.abs(attacker.vel.z - (expect3 - 100)) < 0.01, "прыжок уровня 3: скорость подменяется на 4м")
check(#attacker.sounds == 2 and attacker.sounds[2] == ix.potence.SOUND_FALLBACKS.crack,
	"прыжок уровня 3: добавлен звук удара земли")
attacker.sounds = {}

-- Выбивание двери атакой (StartCommand): двери неуязвимы к урону, поэтому
-- EntityTakeDamage по ним не стреляет — ловим сам замах.
IN_ATTACK = 1
IN_ATTACK2 = 2
traceTarget = nil
util.TraceLine = function() return {Entity = traceTarget} end
local cmdStub = {KeyDown = function() return true end}

PLUGIN:ActivatePotence(attacker, character, 4)
attacker.sounds = {}
local kickedDoor = make_entity("prop_door_rotating", false)
traceTarget = kickedDoor
PLUGIN:StartCommand(attacker, cmdStub)
check(kickedDoor.fired[1] == "unlock" and kickedDoor.fired[2] == "open",
	"уровень 4: замах по двери выбивает её (StartCommand)")
check(#attacker.sounds == 1 and attacker.sounds[1] == ix.potence.SOUND_FALLBACKS.doorKick,
	"выбивание двери: звук")

PLUGIN:ActivatePotence(attacker, character, 3)
local safeDoor = make_entity("prop_door_rotating", false)
traceTarget = safeDoor
PLUGIN:StartCommand(attacker, cmdStub)
check(#safeDoor.fired == 0, "уровень 3: дверь не выбивается")
traceTarget = nil

-- Урон от падения: ноль на время Могущества 2+, обычный без него.
local fallInfo = {damage = 40, type = DMG_FALL}
fallInfo.GetDamage = damageInfo.GetDamage
fallInfo.SetDamage = damageInfo.SetDamage
fallInfo.GetAttacker = function() return nil end
fallInfo.GetInflictor = function() return nil end
fallInfo.GetDamageType = damageInfo.GetDamageType
fallInfo.IsDamageType = damageInfo.IsDamageType
PLUGIN:ActivatePotence(victim, nil, 2)
fallInfo.damage = 40
PLUGIN:EntityTakeDamage(victim, fallInfo)
check(fallInfo.damage == 0, "падение при Могуществе 2+: урон обнулён")
PLUGIN:ClearPotence(victim)
fallInfo.damage = 40
PLUGIN:EntityTakeDamage(victim, fallInfo)
check(fallInfo.damage == 40, "падение без Могущества: урон как обычно")

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
	check(entry.definition.name == "Уровень " .. entry.definition.level,
		entry.id .. ": короткое имя для сегмента колеса")
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
local hudChunk = loadfile(root .. "gamemodes/darkrp_modded/schema/plugins/afterlight_disciplines/libs/cl_buff_hud.lua")
check(hudChunk ~= nil, "cl_buff_hud.lua: синтаксис без ошибок")
local containerChunk = loadfile(root .. "gamemodes/darkrp_modded/schema/plugins/afterlight_disciplines/sh_plugin.lua")
check(containerChunk ~= nil, "контейнер afterlight_disciplines: синтаксис без ошибок")

function Material(path) return {path = path, IsError = function() return false end} end

-- Клиентский порядок включения libs (алфавитный): cl_potence.lua идёт РАНЬШЕ
-- sh_potence_levels.lua. Клиентский файл обязан пережить отсутствие ix.potence.
local clientIncludeOk = pcall(function()
	ix = {}
	PLUGIN = {}
	dofile(base .. "libs/cl_potence.lua")
	dofile(base .. "libs/sh_potence_levels.lua")
	dofile(base .. "libs/cl_potence_hud.lua")
end)
check(clientIncludeOk, "клиентский порядок включения: cl раньше sh — без ошибки")
check(ix.potence ~= nil and ix.potence.CRACK_LIFETIME == 8, "после обоих включений ix.potence собран")

-- Клиентский рантайм: трещина создаётся и рисуется балками без ошибки.
function RealTime() return 0 end
math.Rand = function(a, b) return (a + b) * 0.5 end
local dustParticles = 0
local particleStub = function() return {
	SetVelocity = function() end, SetDieTime = function() end, SetStartAlpha = function() end,
	SetEndAlpha = function() end, SetStartSize = function() end, SetEndSize = function() end,
	SetColor = function() end, SetGravity = function() end, SetAirResistance = function() end
} end
ParticleEmitter = function() return {Add = function() dustParticles = dustParticles + 1 return particleStub() end, Finish = function() end} end
local beamsDrawn = 0
render = {SetMaterial = function() end, DrawBeam = function() beamsDrawn = beamsDrawn + 1 end}

PLUGIN:AddCrack(Vector(100, 200, 0))
check(#ix.potence.cracks == 1, "AddCrack: трещина добавлена")
check(#ix.potence.cracks[1].branches >= 5, "AddCrack: не меньше пяти лучей")
check(dustParticles > 0, "AddCrack: пыль и осколки вздымаются")

local renderHook = hookStore["PostDrawTranslucentRenderables"]
check(renderHook ~= nil, "render-хук трещин зарегистрирован")
if (renderHook) then
	check(pcall(renderHook), "render-хук: отрисовка без ошибки")
	check(beamsDrawn > 0, "render-хук: лучи трещины рисуются балками")
end

-- Пути звуков зарезервированы для будущих файлов.
local joined = table.concat(addedFiles, "|")
check(joined:find("afterlight/disciplines/potence/use.wav", 1, true) ~= nil, "звук использования use.wav зарегистрирован")
check(joined:find("afterlight/disciplines/potence/punch.wav", 1, true) ~= nil, "звук удара punch.wav зарегистрирован")
check(joined:find("afterlight/disciplines/potence/door.wav", 1, true) ~= nil, "звук двери door.wav зарегистрирован")
check(joined:find("afterlight/disciplines/potence/jump_air.wav", 1, true) ~= nil, "зарезервирован звук прыжка")

-- use.wav играет ТОЛЬКО у владельца (PlayFile), фолбэк при отсутствии файла.
local playedFiles = {}
local playFileDecodes = true
sound = {PlayFile = function(path, flags, cb)
	playedFiles[#playedFiles + 1] = path
	if (playFileDecodes) then
		cb({
			flags = flags, volume = 0, stopped = false,
			Play = function(self) self.playing = true end,
			SetVolume = function(self, v) self.volume = v end,
			Stop = function(self) self.stopped = true end
		})
	else
		cb(nil)
	end
end}
check(netHandlers["AfterlightPotenceAreaSound"] ~= nil, "зонный звук удара: обработчик зарегистрирован")
file.Exists = function() return true end
netReadQueue = {ix.potence.SOUND_USE, ix.potence.SOUND_FALLBACKS.activate}
netHandlers["AfterlightPotenceOwnerSound"]()
check(#playedFiles == 1 and playedFiles[1] == "sound/" .. ix.potence.SOUND_USE,
	"use.wav: играет только владелец")
playFileDecodes = false
netReadQueue = {ix.potence.SOUND_USE, ix.potence.SOUND_FALLBACKS.activate}
netHandlers["AfterlightPotenceOwnerSound"]()
check(playedFiles[2] == "sound/" .. ix.potence.SOUND_USE
	and playedFiles[3] == "sound/" .. ix.potence.SOUND_FALLBACKS.activate,
	"декодер не осилил файл: фолбэк вместо тишины")

-- Экранная аура: плавные вход/выход по 1 секунде, отрисовка только пока видна.
local fxClient = make_entity("player", true)
function LocalPlayer() return fxClient end
function FrameTime() return 0.05 end
function ScrW() return 1920 end
function ScrH() return 1080 end
local fxTime = 0
function RealTime() return fxTime end
local fxExistsPaths = {}
file.Exists = function(path) fxExistsPaths[#fxExistsPaths + 1] = path; return true end
local fxDraws = 0
surface = {
	SetDrawColor = function() end,
	SetMaterial = function() end,
	DrawPoly = function() end,
	DrawTexturedRect = function() fxDraws = fxDraws + 1 end
}

local fxHook = hookStore["HUDPaint"]
check(fxHook ~= nil, "аура: HUD-хук зарегистрирован")
fxClient.nw2["afterlightPotenceLevel"] = 3
fxClient.nw2["afterlightPotenceEnd"] = 1e9
for _ = 1, 25 do fxTime = fxTime + 0.05; fxHook() end
check(ix.potence.fx.alpha == 1 and fxDraws > 0, "аура: плавно появляется за 1 секунду и рисуется")
local function FxPathWanted(want)
	for _, path in ipairs(fxExistsPaths) do
		if (path == want) then return true end
	end
	return false
end
check(FxPathWanted("materials/afterlight/disciplines/potence/potence_fx_a.png")
	and FxPathWanted("materials/afterlight/disciplines/potence/potence_fx_b.png")
	and FxPathWanted("materials/afterlight/disciplines/potence/potence_fx_c.png"),
	"аура: материалы ищутся в afterlight/disciplines/potence")
fxClient.nw2["afterlightPotenceLevel"] = 0
for _ = 1, 25 do fxTime = fxTime + 0.05; fxHook() end
check(ix.potence.fx.alpha == 0, "аура: плавно гаснет за 1 секунду")
local drawsAfterFade = fxDraws
fxHook()
check(fxDraws == drawsAfterFade, "аура: после затухания больше не рисуется")

-- Амбиент: цикл на всё время действия, плавный вход после звука активации,
-- плавное затухание и остановка при окончании (время зависит от уровня).
local amb = ix.potence.fx.amb
check(amb ~= nil, "амбиент: состояние доступно")
amb.state = "off"; amb.channel = nil; amb.volume = 0; amb.loading = false
amb.path = nil; amb.pathTry = 0
local loopChannel = nil
local oldPlayFile = sound.PlayFile
sound.PlayFile = function(path, flags, cb)
	playedFiles[#playedFiles + 1] = path
	if (path:find("potence.wav", 1, true)) then
		loopChannel = {
			flags = flags, volume = 0, stopped = false,
			Play = function(self) self.playing = true end,
			SetVolume = function(self, v) self.volume = v end,
			Stop = function(self) self.stopped = true end
		}
		cb(loopChannel)
	else
		cb(nil)
	end
end

fxClient.nw2["afterlightPotenceLevel"] = 2
fxClient.nw2["afterlightPotenceEnd"] = 1e9
for _ = 1, 30 do fxTime = fxTime + 0.05; fxHook() end
check(loopChannel ~= nil and loopChannel.playing, "амбиент: цикл запускается после звука активации")
check(loopChannel ~= nil and loopChannel.flags:find("loop", 1, true) ~= nil, "амбиент: играет циклом")
for _ = 1, 30 do fxTime = fxTime + 0.05; fxHook() end
check(loopChannel ~= nil and loopChannel.volume == ix.potence.AMBIENT_VOLUME,
	"амбиент: плавно набирает рабочую громкость")
fxClient.nw2["afterlightPotenceLevel"] = 0
for _ = 1, 10 do fxTime = fxTime + 0.05; fxHook() end
check(loopChannel.volume > 0 and loopChannel.volume < ix.potence.AMBIENT_VOLUME and !loopChannel.stopped,
	"амбиент: затухает плавно, а не мгновенно")
for _ = 1, 20 do fxTime = fxTime + 0.05; fxHook() end
check(loopChannel.stopped, "амбиент: останавливается после полного затухания")
sound.PlayFile = oldPlayFile

io.write(string.format("Проверок Могущества: %d, провалено: %d\n", checks, failures))
if (failures > 0) then os.exit(1) end
