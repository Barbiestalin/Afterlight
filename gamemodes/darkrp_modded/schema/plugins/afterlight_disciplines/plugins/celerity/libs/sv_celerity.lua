local PLUGIN = PLUGIN

util.AddNetworkString("AfterlightCelerityOwnerSound")

-- Файлы появятся позже; регистрируем пути заранее, чтобы клиенты скачали их
-- сразу после добавления.
resource.AddFile("sound/" .. ix.celerity.SOUND_USE)
resource.AddFile("sound/" .. ix.celerity.SOUND_LOOP)
resource.AddFile("sound/" .. ix.celerity.SOUND_LOOP_LEGACY)

-- Экранная аура скорости: оверлей светлых штрихов (прозрачность в png).
resource.AddFile("materials/afterlight/disciplines/celerity/celerity_fx_a.png")

PLUGIN.soundAvailable = PLUGIN.soundAvailable or {}

local function SoundExists(path)
	local cached = PLUGIN.soundAvailable[path]
	if (cached == nil) then
		cached = file.Exists("sound/" .. path, "GAME") == true
		PLUGIN.soundAvailable[path] = cached
	end
	return cached
end

local function TimerName(client)
	return "AfterlightCelerity." .. (client:SteamID64() or client:EntIndex())
end

local function RemoveTrail(client)
	local trail = client.afterlightCelerityTrail
	if (IsValid(trail)) then
		trail:Remove()
	end
	client.afterlightCelerityTrail = nil
end

function PLUGIN:ClearCelerity(client)
	timer.Remove(TimerName(client))
	client:SetNW2Int("afterlightCelerityLevel", 0)
	client:SetNW2Float("afterlightCelerityEnd", 0)
	client:SetNW2Int("afterlightCelerityDodges", 0)
	RemoveTrail(client)
end

-- Шлейф «разорванного воздуха» (уровни 3+): на 4+ шире и плотнее.
local function SpawnTrail(client, data)
	RemoveTrail(client)
	if ((data.trail or 0) <= 0) then return end
	local big = data.trail >= 2
	-- util.SpriteTrail существует только в server realm; сущность
	-- env_spritetrail реплицируется клиентам сама.
	local trail = util.SpriteTrail(client, 0, Color(214, 232, 248, big and 85 or 50), false,
		big and 26 or 14, big and 6 or 3, 1.2, 0.04, "trails/smoke.vmt")
	if (IsValid(trail)) then
		client.afterlightCelerityTrail = trail
	end
end

-- Активация уровня: повторная активация разрешена и сбрасывает таймер,
-- витэ шлюз интерфейса списывает при каждой активации.
function PLUGIN:ActivateCelerity(client, character, level)
	local data = ix.celerity.GetLevelData(level)
	if (!data or !IsValid(client)) then return false, "notAllowed" end

	client:SetNW2Int("afterlightCelerityLevel", level)
	client:SetNW2Float("afterlightCelerityEnd", CurTime() + data.duration)
	client:SetNW2Int("afterlightCelerityDodges", data.dodge or 0)
	timer.Create(TimerName(client), data.duration, 1, function()
		if (IsValid(client)) then
			self:ClearCelerity(client)
		end
	end)
	SpawnTrail(client, data)
	-- Скорость выставляется в Think ниже (туда же попадает и respawn).
	-- Звук использования слышит ТОЛЬКО сам активировавший: сервер шлёт
	-- персональный net, клиент играет его локально.
	net.Start("AfterlightCelerityOwnerSound")
		net.WriteString(ix.celerity.SOUND_USE)
		net.WriteString(ix.celerity.SOUND_FALLBACKS.activate)
	net.Send(client)
	return true
end

local function IsMeleeWeapon(weapon)
	return weapon:GetClass() == "ix_hands" or weapon.IsMelee == true
end

-- Кулдаун оружия тратится в attack раз быстрее реального времени.
local function ShrinkWeaponTimer(weapon, getter, setter, mult, dt, now)
	local nextAt = getter(weapon)
	if (nextAt and nextAt > now) then
		local remaining = math.max(nextAt - now - (mult - 1) * dt, 0)
		setter(weapon, now + remaining)
	end
end

local lastThink = 0

function PLUGIN:Think()
	local now = CurTime()
	local dt = math.min(math.max(now - lastThink, 0), 0.1)
	lastThink = now

	for _, client in ipairs(player.GetAll()) do
		if (!IsValid(client)) then continue end

		local level = self:GetActiveLevel(client)
		local data = level > 0 and ix.celerity.GetLevelData(level) or nil

		-- Скорость и спринт: множители от базовых значений Helix. Сюда же
		-- попадает respawn во время действия (PlayerSpawn сбрасывает их).
		local baseWalk = ix.config.Get("walkSpeed")
		local baseRun = ix.config.Get("runSpeed")
		local wantWalk = data and math.Round(baseWalk * data.walk) or baseWalk
		local wantRun = data and math.Round(baseRun * data.run) or baseRun
		if (client:GetWalkSpeed() != wantWalk) then
			client:SetWalkSpeed(wantWalk)
		end
		if (client:GetRunSpeed() != wantRun) then
			client:SetRunSpeed(wantRun)
		end

		-- Темп ближнего боя: кулдауны активного милее-оружия сгорают быстрее.
		if (data and data.attack > 1) then
			local weapon = client:GetActiveWeapon()
			if (IsValid(weapon) and IsMeleeWeapon(weapon)) then
				ShrinkWeaponTimer(weapon, weapon.GetNextPrimaryFire, weapon.SetNextPrimaryFire, data.attack, dt, now)
				ShrinkWeaponTimer(weapon, weapon.GetNextSecondaryFire, weapon.SetNextSecondaryFire, data.attack, dt, now)
			end
		end
	end
end

-- Анимации: милее-оружие размахивает быстрее всегда, огнестрел — быстрее
-- крутит анимацию перезарядки, пока зажата клавиша перезарядки.
function PLUGIN:StartCommand(client, cmd)
	local data = nil
	local level = self:GetActiveLevel(client)
	if (level > 0) then
		data = ix.celerity.GetLevelData(level)
	end

	local weapon = client:GetActiveWeapon()
	if (!IsValid(weapon) or !weapon.SetPlaybackRate) then return end

	local rate = 1
	if (data) then
		if (IsMeleeWeapon(weapon)) then
			rate = data.attack
		elseif (data.reload > 1 and cmd:KeyDown(IN_RELOAD)) then
			rate = data.reload
		end
	end

	if (weapon.afterlightPlaybackRate != rate) then
		weapon:SetPlaybackRate(rate)
		weapon.afterlightPlaybackRate = rate
	end
end

-- Уклонения (4+): первые data.dodge попаданий за время действия проходят
-- мимо — персонаж «уходит» из-под удара. На 5-м уровне уклоняется и от пуль.
function PLUGIN:EntityTakeDamage(entity, damageInfo)
	if (!IsValid(entity) or !entity.IsPlayer or !entity:IsPlayer()) then return end

	local level = self:GetActiveLevel(entity)
	if (level < 4) then return end

	local remaining = entity:GetNW2Int("afterlightCelerityDodges", 0)
	if (remaining <= 0) then return end

	local data = ix.celerity.GetLevelData(level)
	local damageType = damageInfo:GetDamageType()
	local melee = bit.band(damageType, DMG_SLASH) != 0 or bit.band(damageType, DMG_CLUB) != 0
	local bullet = bit.band(damageType, DMG_BULLET) != 0 or bit.band(damageType, DMG_BUCKSHOT) != 0

	if (melee or (bullet and data.dodgeBullets)) then
		entity:SetNW2Int("afterlightCelerityDodges", remaining - 1)
		return 0
	end
end
