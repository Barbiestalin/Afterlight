local PLUGIN = PLUGIN

-- Звук и материалы Стойкости раздаются клиентам сразу после добавления.
resource.AddFile("sound/" .. ix.fortitude.SOUND_PATH)
resource.AddFile("materials/afterlight/disciplines/fortitude/fortitude_fx_a.png")
resource.AddFile("materials/afterlight/disciplines/fortitude/fortitude_fx_b.png")
resource.AddFile("materials/afterlight/disciplines/fortitude/shield_frame.png")

local function TimerName(client)
	return "ixFortitudeEnd" .. client:EntIndex()
end

-- Уровень Стойкости из чарлиста (shared-API afterlight_vtm_stats). Пассивный
-- барьер существует, пока в листе есть хотя бы одна точка.
local function SheetLevel(client)
	local character = client:GetCharacter()
	if (!character or !ix.disciplines or !ix.disciplines.GetLevel) then return 0 end
	return math.Clamp(math.floor(tonumber(ix.disciplines.GetLevel(character, "fortitude")) or 0), 0, 5)
end

local function PassiveMax(client)
	local level = SheetLevel(client)
	if (level < 1) then return 0 end
	return ix.fortitude.GetLevelData(level).passive
end

-- Потолок барьера: пассив + добавочный бонус, пока способность активна.
local function ShieldMax(client)
	local maximum = PassiveMax(client)
	local level = PLUGIN:GetActiveLevel(client)
	if (level > 0) then
		maximum = maximum + ix.fortitude.GetLevelData(level).bonus
	end
	return maximum
end

local function SetShield(client, value)
	local maximum = ShieldMax(client)
	value = math.Clamp(math.floor(value + 0.5), 0, maximum)
	client.afterlightFortitudeShield = value
	client:SetNW2Int("afterlightFortitudeShield", value)
	client:SetNW2Int("afterlightFortitudeMax", maximum)
end

function PLUGIN:GetShield(client)
	return client.afterlightFortitudeShield or 0
end

-- Регенерация: барьер ползёт вверх (REGEN_RATE ед./сек), только если персонаж
-- не получал урона REGEN_DELAY секунд. Тик ~5 раз в секунду на игрока.
local function TickShield(client, now, dt)
	if (!client:Alive()) then return end

	local maximum = ShieldMax(client)
	local current = client.afterlightFortitudeShield
	if (current == nil) then
		current = maximum
	end

	if (maximum <= 0) then
		if (current != 0) then
			SetShield(client, 0)
		end
		return
	end

	if (current < maximum and now - (client.afterlightFortitudeLastDamage or 0) >= ix.fortitude.REGEN_DELAY) then
		current = math.min(maximum, current + ix.fortitude.REGEN_RATE * dt)
	end

	if (current != client.afterlightFortitudeShield or
		maximum != client:GetNW2Int("afterlightFortitudeMax", -1)) then
		SetShield(client, current)
	end
end

function PLUGIN:Think()
	local now = CurTime()
	for _, client in ipairs(player.GetAll()) do
		if (now >= (client.afterlightFortitudeNext or 0)) then
			local dt = math.min(now - (client.afterlightFortitudePrev or now), 1)
			client.afterlightFortitudeNext = now + 0.2
			client.afterlightFortitudePrev = now
			TickShield(client, now, dt)
		end
	end
end

-- Барьер принимает урон РАНЬШЕ настоящего здоровья и гасит absorb единиц с
-- каждой атаки (пока способность активна). Любая атака, дошедшая до барьера,
-- сбрасывает паузу регенерации.
function PLUGIN:EntityTakeDamage(entity, damageInfo)
	if (!IsValid(entity) or !entity.IsPlayer or !entity:IsPlayer()) then return end

	local maximum = ShieldMax(entity)
	if (maximum <= 0) then return end

	entity.afterlightFortitudeLastDamage = CurTime()

	local original = damageInfo:GetDamage()
	local incoming = original
	local level = self:GetActiveLevel(entity)
	if (level > 0) then
		incoming = math.max(0, incoming - ix.fortitude.GetLevelData(level).absorb)
	end

	local current = entity.afterlightFortitudeShield or 0
	local absorbed = math.min(current, incoming)
	if (absorbed > 0) then
		SetShield(entity, current - absorbed)
		incoming = incoming - absorbed
	end

	if (incoming != original) then
		damageInfo:SetDamage(incoming)
		if (incoming <= 0) then
			return 0
		end
	end
end

function PLUGIN:ActivateFortitude(client, character, level)
	local data = ix.fortitude.GetLevelData(level)
	if (!data or !IsValid(client)) then return false, "notAllowed" end
	if (SheetLevel(client) < level) then return false, "levelTooLow" end

	client:SetNW2Int("afterlightFortitudeLevel", level)
	client:SetNW2Float("afterlightFortitudeEnd", CurTime() + data.duration)
	-- Бонус прибавляется поверх ТЕКУЩЕГО барьера и не выше passive+bonus
	-- (решения опроса). Звук и экранную рябь клиент ведёт сам по NW2.
	SetShield(client, (client.afterlightFortitudeShield or 0) + data.bonus)

	timer.Create(TimerName(client), data.duration, 1, function()
		if (IsValid(client)) then
			self:ClearFortitude(client)
		end
	end)

	return true
end

function PLUGIN:ClearFortitude(client)
	timer.Remove(TimerName(client))
	client:SetNW2Int("afterlightFortitudeLevel", 0)
	client:SetNW2Float("afterlightFortitudeEnd", 0)
	-- Добавочный бонус сгорает до пассивного потолка (решение опроса).
	SetShield(client, client.afterlightFortitudeShield or 0)
end

function PLUGIN:PlayerSpawn(client)
	client.afterlightFortitudeLastDamage = 0
	client.afterlightFortitudeNext = 0
	client.afterlightFortitudePrev = nil
	SetShield(client, PassiveMax(client))
end
