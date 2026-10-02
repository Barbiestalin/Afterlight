local PLUGIN = PLUGIN

util.AddNetworkString("AfterlightCelerityOwnerSound")

-- Файлы появятся позже; регистрируем пути заранее, чтобы клиенты скачали их
-- сразу после добавления.
resource.AddFile("sound/" .. ix.celerity.SOUND_USE)
resource.AddFile("sound/" .. ix.celerity.SOUND_LOOP)
resource.AddFile("sound/" .. ix.celerity.SOUND_LOOP_LEGACY)

-- Экранная аура скорости и своя текстура трейла «разорванного воздуха».
resource.AddFile("materials/afterlight/disciplines/celerity/celerity_fx_a.png")
resource.AddFile("materials/afterlight/disciplines/celerity/celerity_trail.png")

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

	local anchor = client.afterlightCelerityTrailAnchor
	if (IsValid(anchor)) then
		anchor:Remove()
	end
	client.afterlightCelerityTrailAnchor = nil
end

function PLUGIN:ClearCelerity(client)
	timer.Remove(TimerName(client))
	client:SetNW2Int("afterlightCelerityLevel", 0)
	client:SetNW2Float("afterlightCelerityEnd", 0)
	client:SetNW2Int("afterlightCelerityDodges", 0)
	RemoveTrail(client)
end

-- Шлейф «разорванного воздуха» (уровни 3+): собственная текстура, якорь на
-- кости груди, чтобы шлейф шёл из-за спины, а не из-под ног; на 4+ шире.
local TRAIL_MATERIAL = "afterlight/disciplines/celerity/celerity_trail.png"

local function SpawnTrail(client, data)
	RemoveTrail(client)
	if ((data.trail or 0) <= 0) then return end
	local big = data.trail >= 2

	local anchor = nil
	local bone = client.LookupBone and client:LookupBone("ValveBiped.Bip01_Spine2") or nil
	if (bone and bone > 0) then
		anchor = ents.Create("prop_dynamic")
		if (IsValid(anchor)) then
			anchor:SetModel("models/props_junk/watermelon01.mdl")
			anchor:SetNoDraw(true)
			anchor:SetParent(client, bone)
			anchor:SetLocalPos(vector_origin)
			anchor:Spawn()
		else
			anchor = nil
		end
	end

	-- util.SpriteTrail существует только в server realm; сущность
	-- env_spritetrail реплицируется клиентам сама. Аддитивный режим даёт
	-- свечение собственной текстуры воздуха.
	local trail = util.SpriteTrail(anchor or client, 0, Color(205, 228, 248, big and 120 or 80), true,
		big and 30 or 18, big and 8 or 5, 0.9, 0.06, TRAIL_MATERIAL)
	if (IsValid(trail)) then
		client.afterlightCelerityTrail = trail
		client.afterlightCelerityTrailAnchor = anchor
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

-- Ближний бой: кулаки Helix, оружие с флагом IsMelee и любое оружие без
-- магазина (crowbar и прочие милее-свепы).
local function IsMeleeWeapon(weapon)
	if (weapon:GetClass() == "ix_hands" or weapon.IsMelee == true) then
		return true
	end
	return weapon.GetMaxClip1 ~= nil and weapon:GetMaxClip1() <= 0
end

-- Кулдаун оружия тратится в mult раз быстрее реального времени.
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

		local weapon = client:GetActiveWeapon()
		if (IsValid(weapon)) then
			-- Темп ближнего боя: кулдауны милее сгорают быстрее.
			if (data and data.attack > 1 and IsMeleeWeapon(weapon)) then
				ShrinkWeaponTimer(weapon, weapon.GetNextPrimaryFire, weapon.SetNextPrimaryFire, data.attack, dt, now)
				ShrinkWeaponTimer(weapon, weapon.GetNextSecondaryFire, weapon.SetNextSecondaryFire, data.attack, dt, now)
			end

			-- Перезарядка огнестрела: движок завершает её по таймеру
			-- следующего выстрела — сжимаем его, и перезарядка заканчивается
			-- раньше. Флаг ставится в StartCommand, пока зажата перезарядка.
			if (data and data.reload > 1 and weapon.afterlightReloading) then
				ShrinkWeaponTimer(weapon, weapon.GetNextPrimaryFire, weapon.SetNextPrimaryFire, data.reload, dt, now)
				ShrinkWeaponTimer(weapon, weapon.GetNextSecondaryFire, weapon.SetNextSecondaryFire, data.reload, dt, now)
			end
		end
	end
end

-- Анимации: милее размахивает быстрее всегда; огнестрел быстрее крутит
-- анимацию перезарядки, пока она идёт. Здесь же отмечаем факт перезарядки
-- (зажата клавиша и магазин не полон) для ускорения её таймера в Think.
function PLUGIN:StartCommand(client, cmd)
	local data = nil
	local level = self:GetActiveLevel(client)
	if (level > 0) then
		data = ix.celerity.GetLevelData(level)
	end

	local weapon = client:GetActiveWeapon()
	if (!IsValid(weapon)) then return end

	local reloading = false
	if (data and data.reload > 1 and weapon.GetMaxClip1 ~= nil and weapon:GetMaxClip1() > 0) then
		reloading = cmd:KeyDown(IN_RELOAD) == true and weapon:Clip1() < weapon:GetMaxClip1()
	end
	weapon.afterlightReloading = reloading

	if (!weapon.SetPlaybackRate) then return end
	local rate = 1
	if (data) then
		if (IsMeleeWeapon(weapon)) then
			rate = data.attack
		elseif (reloading) then
			rate = data.reload
		end
	end

	if (weapon.afterlightPlaybackRate != rate) then
		weapon:SetPlaybackRate(rate)
		weapon.afterlightPlaybackRate = rate
	end
end

-- Уклонения (4+): первые data.dodge попаданий за время действия проходят
-- мимо — урон обнуляется в самом damageInfo (Helix игнорирует возврат 0 из
-- хука, поэтому гасим урон именно так). На 5-м уровне уклоняется и от пуль.
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
		damageInfo:SetDamage(0)
		return 0
	end
end
