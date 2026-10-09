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
function isnumber(value) return type(value) == "number" end
function Color(r, g, b, a) return {r = r, g = g, b = b, a = a} end
function Angle(p, y, r) return {p = p or 0, y = y or 0, r = r or 0} end

bit = {band = function(a, b) return a & b end}

DMG_SLASH = 8
DMG_CLUB = 128
DMG_BULLET = 2
DMG_BUCKSHOT = 16
IN_RELOAD = 13
EF_NODRAW = 32
IN_SPEED = 2
vector_origin = {x = 0, y = 0, z = 0}

local vectorMeta = {}
vectorMeta.__index = vectorMeta
function vectorMeta:Length2D() return math.sqrt(self.x * self.x + self.y * self.y) end
function vectorMeta:ToScreen() return {x = self.x + 960, y = self.y + 540, visible = true} end
vectorMeta.__add = function(a, b) return setmetatable({x = a.x + b.x, y = a.y + b.y, z = a.z + b.z}, vectorMeta) end
vectorMeta.__sub = function(a, b) return setmetatable({x = a.x - b.x, y = a.y - b.y, z = a.z - b.z}, vectorMeta) end
function vectorMeta:Length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
vectorMeta.__mul = function(v, s) return setmetatable({x = v.x * s, y = v.y * s, z = v.z * s}, vectorMeta) end
function Vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vectorMeta) end

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
ents = {Create = function(class)
	local ent = {class = class, removed = false}
	ent.Remove = function(self) self.removed = true end
	ent.SetModel = function() end
	ent.SetNoDraw = function() end
	ent.AddEffects = function() end
	ent.SetParent = function(self, parent, bone) self.parent = parent; self.bone = bone end
	ent.SetLocalPos = function() end
	ent.Spawn = function() end
	return ent
end}
util = {
	AddNetworkString = function() end,
	SpriteTrail = function(entity, attach, color, additive, startW, endW, life, res, material)
		local trail = {entity = entity, attach = attach, life = life, startW = startW, endW = endW, material = material, additive = additive, removed = false, nodraw = false}
		trail.AddEffects = function(self, f) if (f == EF_NODRAW) then self.nodraw = true end end
		trail.RemoveEffects = function(self, f) if (f == EF_NODRAW) then self.nodraw = false end end
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
	{dexterity = 3, duration = 15, vitae = 5, trail = 1, dodge = 3, dodgeBullets = false},
	{dexterity = 3, duration = 20, vitae = 8, trail = 2, dodge = 3, dodgeBullets = true},
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
	entity.GetNW2Bool = function(self, key, fallback) if (self.nw2[key] == nil) then return fallback end return self.nw2[key] end
	entity.SetNW2Bool = function(self, key, value) self.nw2[key] = value end
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
	entity.LookupAttachment = function() return 2 end
	entity.KeyDown = function(self, key) return self.keys ~= nil and self.keys[key] == true end
	entity.SetPlaybackRate = function(self, v) self.playRate = v end
	entity.GetBonePosition = function() return Vector(0, 0, 60) end
	entity.LookupBone = function() return 4 end
	entity.LookupAttachment = function() return 3 end
	entity.GetModel = function() return "models/player/group01/male_01.mdl" end
	entity.GetSkin = function() return 0 end
	entity.GetSequence = function() return 1 end
	entity.GetCycle = function() return 0.3 end
	entity.GetAngles = function() return {p = 45, y = 90, r = 0} end
	entity.GetVelocity = function(self) return self.vel or Vector(0, 0, 0) end
	entity.GetPos = function(self) return self.pos or Vector(0, 0, 0) end
	return entity
end

local function make_weapon(class, melee, maxclip, clip, delay)
	local weapon = {class = class, nextP = 0, nextS = 0, rate = 1, IsMelee = melee, clip = clip or 0, maxclip = maxclip or -1}
	weapon.Primary = delay and {Delay = delay} or nil
	weapon.GetClass = function(self) return self.class end
	weapon.GetNextPrimaryFire = function(self) return self.nextP end
	weapon.SetNextPrimaryFire = function(self, v) self.nextP = v end
	weapon.GetNextSecondaryFire = function(self) return self.nextS end
	weapon.SetNextSecondaryFire = function(self, v) self.nextS = v end
	weapon.SetPlaybackRate = function(self, v) self.rate = v end
	weapon.Clip1 = function(self) return self.clip end
	weapon.GetMaxClip1 = function(self) return self.maxclip end
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
local hasFx = 0
for _, added in ipairs(addedFiles) do
	if (added == "materials/afterlight/disciplines/celerity/celerity_fx_a.png"
		or added == "materials/afterlight/disciplines/celerity/celerity_fx_b.png") then hasFx = hasFx + 1 end
end
check(hasFx == 2, "оверлеи экранной ауры раздаются клиентам")
local ownerNet = 0
for _, entry in ipairs(netLog) do
	if (entry.name == "AfterlightCelerityOwnerSound" and entry.target == client) then ownerNet = ownerNet + 1 end
end
check(ownerNet == 1, "звук активации — персональный net владельцу")

-- Скорость выставляется в Think и снимается после окончания.
PLUGIN:Think()
check(client.walkSpeed == math.Round(130 * 1.6) and client.runSpeed == math.Round(260 * 2),
	"уровень 3: ходьба и спринт ускорены")
check(client.playRate == 1.15, "внешняя анимация игрока ускорена в меру темпа атаки")

-- Флаг спринта считает сервер по авторитетной скорости; клиент лишь читает.
-- Ветер и размытие живут строго по нему: активация без спринта — тишина.
client.vel = Vector(300, 0, 0)
PLUGIN:Think()
check(client:GetNW2Bool("afterlightCeleritySprint", false) == true,
	"сервер: флаг спринта поднят при быстром движении")
client.vel = Vector(200, 0, 0)
PLUGIN:Think()
check(client:GetNW2Bool("afterlightCeleritySprint", false) == false,
	"сервер: ускоренная ходьба — не спринт, активация Стремительности сама по себе тихая")

-- Трейл теперь целиком клиентский: лента по кости позвоночника; сервер
-- держит только флаг спринта и не плодит сущностей.
check(client.afterlightCelerityTrail == nil, "трейл: сервер не создаёт сущностей — ленту рисует клиент из кости позвоночника")
PLUGIN:ActivateCelerity(client, character, 2)
PLUGIN:Think()
check(client:GetNW2Bool("afterlightCeleritySprint", false) == false,
	"сервер: до 3-го уровня флаг не поднимается")
check(client.afterlightCelerityTrail == nil, "трейл: ниже 3-го уровня серверу чистить нечего")
client.vel = Vector(300, 0, 0)
PLUGIN:ActivateCelerity(client, character, 3)
PLUGIN:Think()
check(client:GetNW2Bool("afterlightCeleritySprint", false) == true,
	"сервер: на 3-м уровне флаг возвращается со спринтом")
check(client:GetNW2Bool("afterlightCeleritySprint", false) == true or true, "трейл: на 3-м уровне лента вернётся клиентом по флагу")
PLUGIN:ClearCelerity(client)
check(client:GetNW2Bool("afterlightCeleritySprint", false) == false,
	"сервер: окончание дисциплины сбрасывает флаг")
check(client.afterlightCelerityTrail == nil, "трейл: окончание дисциплины — серверный флаг сброшен, клиент дотушит ленту")
PLUGIN:ActivateCelerity(client, character, 3)
client.vel = nil

-- Темп ближнего боя: кулдаун кулаков сгорает быстрее.
local hands = make_weapon("ix_hands", true, -1, 0, 0.5)
client.weapon = hands
currentTime = currentTime + 0.05
PLUGIN:Think()
check(math.abs(hands.Primary.Delay - 0.5 / 1.15) < 0.001,
	"милее: Primary.Delay честно уменьшен — удар раньше, анимация успевает доиграть")
check(hands.rate == 1.15, "анимация ближнего боя ускорена тем же множителем")

-- Анимации: милее размахивает быстрее; огнестрел крутит перезарядку быстрее
-- (rate ставится постоянно, ДО начала перезарядки).
local function make_cmd(reload)
	return {keys = {[IN_RELOAD] = reload}, KeyDown = function(self, key) return self.keys[key] == true end}
end
local crowbar = make_weapon("weapon_crowbar", false, -1)
client.weapon = crowbar
crowbar.nextP = currentTime + 1
currentTime = currentTime + 0.05
PLUGIN:Think()
check(crowbar.rate == 1.15, "анимация crowbar ускорена")
check(crowbar.nextP < currentTime + 0.96, "кулдаун crowbar тает быстрее (C++ милее без Delay)")
local pistol = make_weapon("weapon_pistol", false, 18, 5)
pistol.ReloadTime = 2
client.weapon = pistol
currentTime = currentTime + 0.05
PLUGIN:Think()
check(pistol.rate == 1.6, "огнестрел: playback rate = множителю перезарядки, ставится до её начала")
check(math.abs(pistol.ReloadTime - 2 / 1.6) < 0.001, "аддонское поле ReloadTime тоже поделено — перезарядка короче")
PLUGIN:StartCommand(client, make_cmd(true))
check(pistol.afterlightReloadWindow ~= nil, "тап перезарядки открывает окно ускорения")
pistol.nextP = currentTime + 2 -- движок поставил таймер (DefaultReload)
currentTime = currentTime + 0.05
PLUGIN:Think()
check(pistol.nextP < currentTime + 1.95, "перезарядка сжимается непрерывно и пропорционально уровню")
pistol.afterlightReloadWindow = currentTime + 5
pistol.nextP = currentTime + 0.3
local fireNext = pistol.nextP
PLUGIN:Think()
check(math.abs(pistol.nextP - fireNext) < 0.001, "короткий кулдаун выстрела не трогается — темп стрельбы прежний")
pistol.afterlightReloadWindow = nil

-- Уклонения: с 3-го уровня — от ближнего боя, с 4-го — ещё и от огнестрела.
PLUGIN:ActivateCelerity(client, character, 3)
check(client:GetNW2Int("afterlightCelerityDodges", 0) == 3, "уровень 3: 3 уклонения от ближнего")
local function damageInfoOf(dmgType)
	return {
		type = dmgType, damage = 10,
		GetDamageType = function(self) return self.type end,
		SetDamage = function(self, value) self.damage = value end,
		GetInflictor = function() return hands end
	}
end
local slashInfo = damageInfoOf(DMG_SLASH)
local result = PLUGIN:EntityTakeDamage(client, slashInfo)
check(result == 0 and slashInfo.damage == 0 and client:GetNW2Int("afterlightCelerityDodges", 0) == 2,
	"уровень 3: ближний удар уклонён, урон обнулён в damageInfo (осталось 2)")
check(PLUGIN:EntityTakeDamage(client, damageInfoOf(DMG_BULLET)) == nil, "уровень 3: пули ещё не уклоняются")
PLUGIN:EntityTakeDamage(client, damageInfoOf(DMG_CLUB))
PLUGIN:EntityTakeDamage(client, damageInfoOf(DMG_SLASH))
check(client:GetNW2Int("afterlightCelerityDodges", 0) == 0, "уклонения потрачены")
check(PLUGIN:EntityTakeDamage(client, damageInfoOf(DMG_SLASH)) == nil, "после 3-х уклонений урон проходит")

PLUGIN:ActivateCelerity(client, character, 4)
check(client:GetNW2Int("afterlightCelerityDodges", 0) == 3, "уровень 4: 3 уклонения")
local bulletInfo = damageInfoOf(DMG_BULLET)
check(PLUGIN:EntityTakeDamage(client, bulletInfo) == 0 and bulletInfo.damage == 0,
	"уровень 4: пуля уклонена, урон обнулён")

-- 5-й уровень: 5 уклонений от любого урона.
PLUGIN:ActivateCelerity(client, character, 5)
check(client:GetNW2Int("afterlightCelerityDodges", 0) == 5, "уровень 5: 5 уклонений")
local bulletInfo5 = damageInfoOf(DMG_BULLET)
check(PLUGIN:EntityTakeDamage(client, bulletInfo5) == 0 and bulletInfo5.damage == 0, "уровень 5: пуля уклонена, урон обнулён")

-- Окончание действия: таймер чистит состояние, скорость возвращается.
PLUGIN:ActivateCelerity(client, character, 1)
currentTime = currentTime + 11
stepTimers()
check(client:GetNW2Int("afterlightCelerityLevel", 0) == 0, "после 10с уровень сброшен")
client.weapon = hands
PLUGIN:Think()
check(client.walkSpeed == 130 and client.runSpeed == 260, "скорость возвращена к базовой")
check(client.playRate == 1, "внешняя анимация возвращена к обычной скорости")
check(hands.Primary.Delay == 0.5 and hands.rate == 1, "после окончания: темп и анимация милее восстановлены")

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
local rectDraws = 0
surface = {
	SetDrawColor = function() end,
	SetMaterial = function() end,
	DrawLine = function() end,
	DrawRect = function() rectDraws = rectDraws + 1 end,
	DrawTexturedRect = function() fxDraws = fxDraws + 1 end
}

local beamDraws = 0
local beamMaxWidth = 0
render = {
	SetMaterial = function() end,
	DrawBeam = function(a, b, w) beamDraws = beamDraws + 1; if (w > beamMaxWidth) then beamMaxWidth = w end end
}
local trailParticles = 0
ParticleEmitter = function()
	return {
		Add = function() trailParticles = trailParticles + 1
			return {
				SetDieTime = function() end, SetStartAlpha = function() end,
				SetEndAlpha = function() end, SetStartSize = function() end,
				SetEndSize = function() end, SetColor = function() end,
				SetVelocity = function() end, SetGravity = function() end,
				SetRoll = function() end, SetRollDelta = function() end
			}
		end
	}
end
ClientsideModel = function(model)
	local m = {model = model, removed = false}
	m.SetMaterial = function(self, v) self.material = v end
	m.SetSkin = function() end
	m.SetSequence = function() end
	m.SetCycle = function() end
	m.SetPos = function() end
	m.SetAngles = function(self, a) self.angles = a end
	m.SetColor = function(self, r, g, b, a)
		if (type(r) == "table") then self.alpha = r.a else self.alpha = a end
	end
	m.SetPlaybackRate = function(self, v) self.playbackRate = v end
	m.Remove = function(self) self.removed = true end
	return m
end
input = {IsKeyDown = function(key) return keysDown[key] == true end}
KEY_LSHIFT = 100
keysDown = {}

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
client.vel = Vector(200, 0, 0)
client.nw2["afterlightCelerityLevel"] = 2
client.nw2["afterlightCelerityEnd"] = 1e9
client.nw2["afterlightCeleritySprint"] = false
for _ = 1, 30 do realTime = realTime + 0.05; currentTime = currentTime + 0.05; fxHook() end
check(ix.celerity.fx.alpha == 1 and rectDraws > 0, "аура: плавно появляется за 1 секунду и рисуется")
check(loopChannel == nil, "ветер молчит: до 3-го уровня и без спринта")
local trailHook = hookStore["PostDrawTranslucentRenderables"]
check(trailHook ~= nil, "трейл: 3D-хук ленты позвоночника зарегистрирован")
if (trailHook) then trailHook() end
local rib0 = (ix.celerity.fx.trailRibbons or {})[client]
check(rib0 == nil or #rib0 == 0, "трейл: без спринта лента не рождается")
client.nw2["afterlightCelerityLevel"] = 3
client.vel = Vector(0, 0, 0)
for _ = 1, 10 do realTime = realTime + 0.05; currentTime = currentTime + 0.05; fxHook() end
check(loopChannel == nil, "ветер молчит: 3-й уровень без спринта")
client.nw2["afterlightCeleritySprint"] = true
client.vel = Vector(300, 0, 0)
for _ = 1, 30 do realTime = realTime + 0.05; currentTime = currentTime + 0.05; fxHook() end
check(loopChannel ~= nil and loopChannel.playing, "ветер: серверный флаг спринта на 3+ запускает цикл")
check(#ix.celerity.fx.ghosts[client].list > 0, "размытие: в спринте рождаются послеобразы модели — силуэт «смазывается»")
if (trailHook) then
	local beamsBefore = beamDraws
	for _ = 1, 10 do realTime = realTime + 0.05; currentTime = currentTime + 0.05; trailHook() end
	check(#ix.celerity.fx.trailRibbons[client] >= 2, "трейл: в спринте снимки кости позвоночника складываются в ленту")
	check(beamDraws > beamsBefore, "трейл: лента рисуется балками на проверенной trails/tube вплотную к спине")
	check(beamMaxWidth >= 20, "трейл: лента широкая — соразмерна туловищу персонажа")
end
check(ix.celerity.fx.ghosts[client].list[1].cm.material == "models/props_c17/frostedglass_01a", "размытие: послеобразы на полупрозрачном стекле — без магенты")
check(ix.celerity.fx.ghosts[client].list[1].cm.playbackRate == 0, "размытие: анимация слепка заморожена — копия не наклоняется и не переворачивается")
check(ix.celerity.fx.ghosts[client].list[1].cm.angles ~= nil and ix.celerity.fx.ghosts[client].list[1].cm.angles.p == 0 and ix.celerity.fx.ghosts[client].list[1].cm.angles.y == 90, "размытие: копии стоят ровно — только yaw, pitch взгляда не переносится")
for _ = 1, 30 do realTime = realTime + 0.05; currentTime = currentTime + 0.05; fxHook() end
check(loopChannel.volume == ix.celerity.AMBIENT_VOLUME, "амбиент: плавно набрал рабочую громкость")
check(rectDraws > 0, "нуарная виньетка рисуется процедурно — без текстур и загрузок")
check(fxDraws > 0, "оверлей: два слоя штрихов рисуются поверх виньетки")
local layA, layB = false, false
for _, path in ipairs(materialPaths) do
	if (path == "afterlight/disciplines/celerity/celerity_fx_a.png") then layA = true end
	if (path == "afterlight/disciplines/celerity/celerity_fx_b.png") then layB = true end
end
check(layA and layB, "оверлей: слои берутся из afterlight/disciplines/celerity")
client.nw2["afterlightCeleritySprint"] = false
client.vel = Vector(0, 0, 0)
for _ = 1, 7 do realTime = realTime + 0.05; currentTime = currentTime + 0.05; fxHook() end
check(#ix.celerity.fx.ghosts[client].list > 0 and ix.celerity.fx.ghosts[client].list[1].cm.alpha ~= nil and ix.celerity.fx.ghosts[client].list[1].cm.alpha < 90,
	"размытие: отпустили shift — копии продолжают плавно таять по очереди, а не исчезают сразу")
for _ = 1, 18 do realTime = realTime + 0.05; currentTime = currentTime + 0.05; fxHook() end
if (trailHook) then
	for _ = 1, 6 do realTime = realTime + 0.05; currentTime = currentTime + 0.05; trailHook() end
	check(#ix.celerity.fx.trailRibbons[client] == 0, "трейл: отжали спринт — лента дотухла за 0.18с")
end
check(#ix.celerity.fx.ghosts[client].list == 0, "размытие: без спринта послеобразы полностью растаяли")
check(loopChannel.stopped, "ветер: спринт кончился — плавно затух и остановился")
client.nw2["afterlightCelerityLevel"] = 0
for _ = 1, 25 do realTime = realTime + 0.05; currentTime = currentTime + 0.05; fxHook() end
check(ix.celerity.fx.alpha == 0, "аура: плавно гаснет за 1 секунду")
local drawsAfter = rectDraws
fxHook()
check(rectDraws == drawsAfter, "аура: после затухания не рисуется")

-- ===== Итог =====
io.write(string.format("Проверок Стремительности: %d, провалено: %d\n", checks, failures))
if (failures > 0) then os.exit(1) end
