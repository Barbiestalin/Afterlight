-- Стенд плагина Стойкости: исполняет РЕАЛЬНЫЕ файлы плагина (таблица
-- уровней, регистрация способностей, серверная механика барьера, клиентский
-- HUD/звук) на заглушках GMod-окружения и сверяет поведение с ТЗ и опросом.
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
		local probe = io.open(prefix .. "tests/afterlight_fortitude/run_fortitude.lua", "r")
		if (probe) then
			probe:close()
			return prefix
		end
	end
	return ""
end

local root = find_root()
local base = root .. "gamemodes/darkrp_modded/schema/plugins/afterlight_disciplines/plugins/fortitude/"

-- ===== Заглушки окружения =====
ix = {}
math.Clamp = function(value, lo, hi) return math.min(math.max(value, lo), hi) end
function isfunction(value) return type(value) == "function" end
function istable(value) return type(value) == "table" end
function isstring(value) return type(value) == "string" end
function isnumber(value) return type(value) == "number" end
function Color(r, g, b, a) return {r = r, g = g, b = b, a = a} end
TEXT_ALIGN_CENTER = 1

local currentTime = 1000
function CurTime() return currentTime end
function RealTime() return currentTime end
function IsValid(entity) return entity ~= nil and entity ~= false and entity.removed ~= true end
function Lerp(a, b, c) return b + (c - b) * a end
function FrameTime() return 0.016 end
function ScrW() return 1920 end
function ScrH() return 1080 end
function ErrorNoHalt(...) io.write(...) end

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

addedFiles = {}
resource = {AddFile = function(path) addedFiles[#addedFiles + 1] = path end}

sheetLevel = 2
local registeredPowers = {}
ix.disciplines = {
	RegisterPower = function(disciplineID, powerID, definition)
		registeredPowers[#registeredPowers + 1] = {discipline = disciplineID, id = powerID, definition = definition}
	end,
	GetLevel = function(character, disciplineID) return sheetLevel end
}

playersList = {}
player = {GetAll = function() return playersList end}

local function make_client(index)
	local client = {index = index, removed = false, alive = true}
	client.nw2 = {}
	client.IsPlayer = function() return true end
	client.EntIndex = function(self) return self.index end
	client.Alive = function(self) return self.alive end
	client.GetCharacter = function(self) return self.character end
	client.GetNW2Int = function(self, key, def) return self.nw2[key] or def end
	client.SetNW2Int = function(self, key, value) self.nw2[key] = value end
	client.GetNW2Float = function(self, key, def) return self.nw2[key] or def end
	client.SetNW2Float = function(self, key, value) self.nw2[key] = value end
	local character = {player = client}
	character.GetPlayer = function(self) return self.player end
	character.IsVampire = function() return true end
	client.character = character
	playersList[#playersList + 1] = client
	return client
end

local function damageInfoOf(amount)
	local info = {damage = amount}
	info.GetDamage = function(self) return self.damage end
	info.SetDamage = function(self, value) self.damage = value end
	return info
end

-- Клиентские заглушки рисования/звука (логируют вызовы).
surfaceLog = {}
surface = {
	CreateFont = function() end,
	SetMaterial = function(material) surfaceLog.material = material and material.path end,
	SetDrawColor = function(r, g, b, a) surfaceLog.color = {r = r, g = g, b = b, a = a} end,
	DrawTexturedRect = function(x, y, w, h)
		surfaceLog[#surfaceLog + 1] = {kind = "textured", material = surfaceLog.material, w = w, h = h}
	end,
	DrawRect = function(x, y, w, h) surfaceLog[#surfaceLog + 1] = {kind = "rect", w = w} end
}
drawLog = {}
draw = {
	RoundedBox = function(r, x, y, w, h, color) drawLog[#drawLog + 1] = {kind = "box", w = w, h = h} end,
	SimpleText = function(text, font, x, y, color) drawLog[#drawLog + 1] = {kind = "text", text = text} end
}
function Material(path) return {path = path} end
playLog = {}
sound = {
	PlayFile = function(path, flags, callback)
		playLog[#playLog + 1] = path
		callback({SetVolume = function() end, Play = function() end})
	end
}
ix.gui = {}

-- ===== Таблица уровней (реальный файл) =====
PLUGIN = {}
dofile(base .. "libs/sh_fortitude_levels.lua")

local spec = {
	{passive = 25, bonus = 25, absorb = 5, stamina = 1, duration = 10, vitae = 4, cooldown = 30},
	{passive = 35, bonus = 35, absorb = 10, stamina = 1, duration = 12, vitae = 6, cooldown = 30},
	{passive = 45, bonus = 45, absorb = 15, stamina = 2, duration = 15, vitae = 10, cooldown = 30},
	{passive = 60, bonus = 70, absorb = 20, stamina = 3, duration = 15, vitae = 12, cooldown = 30},
	{passive = 70, bonus = 100, absorb = 25, stamina = 4, duration = 20, vitae = 15, cooldown = 40}
}
for level, expected in ipairs(spec) do
	local data = ix.fortitude.GetLevelData(level)
	check(data and data.passive == expected.passive and data.bonus == expected.bonus
		and data.absorb == expected.absorb and data.stamina == expected.stamina
		and data.duration == expected.duration and data.vitae == expected.vitae
		and data.cooldown == expected.cooldown,
		"уровень " .. level .. ": барьер/бонус/поглощение/Выносливость/время/витэ/откат по ТЗ")
end
check(ix.fortitude.REGEN_RATE == 5 and ix.fortitude.REGEN_DELAY == 20,
	"регенерация: 5 ед/сек после 20 секунд без урона (решение опроса)")

-- ===== Регистрация способностей (реальный sh_plugin) =====
dofile(base .. "sh_plugin.lua")
PLUGIN:InitializedPlugins()

check(#registeredPowers == 5 and registeredPowers[1].discipline == "fortitude",
	"колесо: зарегистрированы 5 способностей дисциплины fortitude")
local cooldownsOk, vitaeOk = true, true
for i, power in ipairs(registeredPowers) do
	if (power.definition.cooldown ~= spec[i].cooldown) then cooldownsOk = false end
	if (power.definition.GetVitaeCost() ~= spec[i].vitae) then vitaeOk = false end
end
check(cooldownsOk, "колесо: откаты 30/30/30/30/40 секунд (ТЗ)")
check(vitaeOk, "колесо: стоимость 4/6/10/12/15 витэ (ТЗ)")

-- ===== Сервер (реальный sv_fortitude) =====
dofile(base .. "libs/sv_fortitude.lua")

local hasSound, hasMaterials = false, 0
for _, path in ipairs(addedFiles) do
	if (path == "sound/" .. ix.fortitude.SOUND_PATH) then hasSound = true end
	if (path:find("materials/afterlight/disciplines/fortitude/") == 1) then hasMaterials = hasMaterials + 1 end
end
check(hasSound, "раздача: звук дисциплины регистрируется для клиентов")
check(hasMaterials >= 3, "раздача: каменная кайма, рябь и рамка индикатора регистрируются")

local client = make_client(1)

PLUGIN:Think()
check(PLUGIN:GetShield(client) == 35 and client:GetNW2Int("afterlightFortitudeMax", 0) == 35,
	"пассив: 2 точки чарлиста дают барьер 35 сразу")

check(PLUGIN:ActivateFortitude(client, client.character, 3) == false,
	"активация выше точек чарлиста отклоняется")

check(PLUGIN:ActivateFortitude(client, client.character, 2) == true,
	"активация 2 уровня разрешена")
check(client:GetNW2Int("afterlightFortitudeLevel", 0) == 2, "активация: NW2-уровень выставлен")
check(PLUGIN:GetShield(client) == 70 and client:GetNW2Int("afterlightFortitudeMax", 0) == 70,
	"активация: бонус 35 поверх текущих 35, потолок 70")
check(PLUGIN:GetCharacterVTMStatBonus(client.character, "stamina") == 1,
	"статы: временная Выносливость +1 видна чарлисту")
check(PLUGIN:GetCharacterVTMStatBonus(client.character, "strength") == nil,
	"статы: бонус только к Выносливости")

local hit = damageInfoOf(30)
check(PLUGIN:EntityTakeDamage(client, hit) == 0 and hit:GetDamage() == 0,
	"урон 30: поглощение 10 и барьер гасят остаток — урона нет")
check(PLUGIN:GetShield(client) == 50, "урон 30: барьер 70 -> 50")

hit = damageInfoOf(100)
PLUGIN:EntityTakeDamage(client, hit)
check(hit:GetDamage() == 40 and PLUGIN:GetShield(client) == 0,
	"урон 100: 10 гасится способностью, 50 барьером, в здоровье проходит 40")

local blockedAt = currentTime
for _ = 1, 25 do currentTime = currentTime + 0.2; PLUGIN:Think() end
check(PLUGIN:GetShield(client) == 0, "регенерация: после урона 20 секунд пауза — барьер не растёт")

currentTime = blockedAt + 21
client.afterlightFortitudePrev = currentTime
for _ = 1, 6 do currentTime = currentTime + 0.2; PLUGIN:Think() end
check(PLUGIN:GetShield(client) == 6, "регенерация: 5 ед/сек после паузы (6 тиков по 0.2с -> +6)")

client.afterlightFortitudeShield = 60
currentTime = currentTime + 100
stepTimers()
check(client:GetNW2Int("afterlightFortitudeLevel", 0) == 0, "окончание: активный уровень сброшен")
check(PLUGIN:GetShield(client) == 35 and client:GetNW2Int("afterlightFortitudeMax", 0) == 35,
	"окончание: бонус сгорел до пассивного потолка 35 (решение опроса)")

sheetLevel = 0
PLUGIN:Think()
check(PLUGIN:GetShield(client) == 0 and client:GetNW2Int("afterlightFortitudeMax", 0) == 0,
	"без точек Стойкости в чарлисте барьера нет")
check(PLUGIN:ActivateFortitude(client, client.character, 1) == false,
	"без точек в чарлисте активация отклоняется")

sheetLevel = 2
client.afterlightFortitudeShield = 10
PLUGIN:PlayerSpawn(client)
check(PLUGIN:GetShield(client) == 35, "возрождение: барьер возвращается к пассивному максимуму")

-- ===== Клиент (реальный cl_fortitude) =====
function LocalPlayer() return client end

dofile(base .. "libs/cl_fortitude.lua")
local hudHook = hookStore["HUDPaint"]
check(isfunction(hudHook), "клиент: HUD-хук Стойкости зарегистрирован")

-- Барьера нет (максимум 0) — индикатор и звук молчат.
client.nw2 = {}
drawLog, playLog, surfaceLog = {}, {}, {}
hudHook()
local texts = 0
for _, entry in ipairs(drawLog) do
	if (entry.kind == "text" and entry.text == "ЩИТ СТОЙКОСТИ") then texts = texts + 1 end
end
check(texts == 0 and #playLog == 0, "клиент: без барьера индикатор и звук не рисуются/не играют")

-- Активация: звук один раз, каменная кайма и индикатор с подписью.
client:SetNW2Int("afterlightFortitudeMax", 70)
client:SetNW2Int("afterlightFortitudeShield", 70)
client:SetNW2Int("afterlightFortitudeLevel", 2)
client:SetNW2Float("afterlightFortitudeEnd", currentTime + 12)
drawLog, playLog, surfaceLog = {}, {}, {}
hudHook()
check(#playLog == 1 and playLog[1]:find("fortitude%.wav") ~= nil,
	"клиент: переход 0->2 проигрывает fortitude.wav")
hudHook()
check(#playLog == 1, "клиент: повторный кадр не запускает звук второй раз")

local aura, caption, value = false, false, false
for _, entry in ipairs(surfaceLog) do
	if (entry.kind == "textured" and entry.material and entry.material:find("fortitude_fx_a")) then aura = true end
end
for _, entry in ipairs(drawLog) do
	if (entry.kind == "text") then
		if (entry.text == "ЩИТ СТОЙКОСТИ") then caption = true end
		if (entry.text == "70 / 70") then value = true end
	end
end
check(aura, "клиент: каменная кайма (рябь окаменелости) рисуется на время действия")
check(caption, "клиент: индикатор подписан «ЩИТ СТОЙКОСТИ»")
check(value, "клиент: индикатор показывает количество временных хп (70 / 70)")

io.write(string.format("Проверок Стойкости: %d, провалено: %d\n", checks, failures))
if (failures > 0) then os.exit(1) end
