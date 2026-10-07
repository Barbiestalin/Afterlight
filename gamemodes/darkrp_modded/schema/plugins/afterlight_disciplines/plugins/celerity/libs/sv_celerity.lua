local PLUGIN = PLUGIN

util.AddNetworkString("AfterlightCelerityOwnerSound")

-- Файлы появятся позже; регистрируем пути заранее, чтобы клиенты скачали их
-- сразу после добавления.
resource.AddFile("sound/" .. ix.celerity.SOUND_USE)
resource.AddFile("sound/" .. ix.celerity.SOUND_LOOP)
resource.AddFile("sound/" .. ix.celerity.SOUND_LOOP_LEGACY)

-- Текстура штрихов ветра для клиентского трейла (сам трейл рисует клиент).
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

function PLUGIN:ClearCelerity(client)
	timer.Remove(TimerName(client))
	client:SetNW2Int("afterlightCelerityLevel", 0)
	client:SetNW2Float("afterlightCelerityEnd", 0)
	client:SetNW2Int("afterlightCelerityDodges", 0)
	-- Внешняя анимация возвращается к обычной скорости.
	if (client.afterlightRate ~= 1) then
		client:SetPlaybackRate(1)
		client.afterlightRate = 1
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
	-- Скорость и playback rate выставляются в Think ниже (туда же попадает
	-- и respawn). Звук использования слышит ТОЛЬКО сам активировавший.
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

		-- Вся анимация игрока (взмахи снаружи, циклы бега) идёт быстрее —
		-- и у владельца, и у окружающих, поэтому внешняя анимация и звуки
		-- ударов не ломаются при ускоренном темпе атаки.
		local wantRate = data and data.attack or 1
		if (client.afterlightRate != wantRate) then
			client:SetPlaybackRate(wantRate)
			client.afterlightRate = wantRate
		end

		local weapon = client:GetActiveWeapon()
		if (!IsValid(weapon)) then continue end

		-- Темп ближнего боя: кулдауны сгорают быстрее; анимация владельца
		-- (включая вьюмодель) ускорена тем же множителем.
		if (data and data.attack > 1 and IsMeleeWeapon(weapon)) then
			ShrinkWeaponTimer(weapon, weapon.GetNextPrimaryFire, weapon.SetNextPrimaryFire, data.attack, dt, now)
			ShrinkWeaponTimer(weapon, weapon.GetNextSecondaryFire, weapon.SetNextSecondaryFire, data.attack, dt, now)
		end

		-- Перезарядка огнестрела: тап R открывает «окно» перезарядки; пока
		-- оно открыто и таймер следующего выстрела похож на перезарядку
		-- (>0.4с), он непрерывно сжимается в reload раз — пропорционально
		-- уровню. Завершение перезарядки движок ждёт по этому таймеру.
		if (data and data.reload > 1 and weapon.afterlightReloadWindow
			and weapon.afterlightReloadWindow > now) then
			local clipFull = weapon.GetMaxClip1 ~= nil and weapon:Clip1() >= weapon:GetMaxClip1()
			local nextAt = weapon.GetNextPrimaryFire and weapon:GetNextPrimaryFire() or 0
			if (clipFull or nextAt <= now) then
				weapon.afterlightReloadWindow = nil
			elseif (nextAt - now > 0.4) then
				ShrinkWeaponTimer(weapon, weapon.GetNextPrimaryFire, weapon.SetNextPrimaryFire, data.reload, dt, now)
				ShrinkWeaponTimer(weapon, weapon.GetNextSecondaryFire, weapon.SetNextSecondaryFire, data.reload, dt, now)
			end
		end
	end
end

function PLUGIN:StartCommand(client, cmd)
	local data = nil
	local level = self:GetActiveLevel(client)
	if (level > 0) then
		data = ix.celerity.GetLevelData(level)
	end

	local weapon = client:GetActiveWeapon()
	if (!IsValid(weapon)) then return end

	-- Тап перезарядки (клавиша нажата, магазин не полон) открывает окно,
	-- в котором Think сжимает таймер перезарядки.
	if (data and data.reload > 1 and weapon.GetMaxClip1 ~= nil and weapon:GetMaxClip1() > 0
		and cmd:KeyDown(IN_RELOAD) == true and weapon:Clip1() < weapon:GetMaxClip1()) then
		weapon.afterlightReloadWindow = CurTime() + 6
	end

	-- Вьюмодель ближнего боя размахивает быстрее для владельца; внешняя
	-- анимация ускорена через playback rate самого игрока (Think).
	local rate = 1
	if (data and IsMeleeWeapon(weapon)) then
		rate = data.attack
	end
	if (weapon.SetPlaybackRate and weapon.afterlightPlaybackRate != rate) then
		weapon:SetPlaybackRate(rate)
		weapon.afterlightPlaybackRate = rate
	end
end

-- Уклонения (3+): первые data.dodge попаданий за время действия проходят
-- мимо — урон обнуляется в самом damageInfo (Helix игнорирует возврат 0 из
-- хука, поэтому гасим урон именно так). С 3-го уровня уклоняется от ближнего
-- боя, с 4-го — ещё и от огнестрела.
function PLUGIN:EntityTakeDamage(entity, damageInfo)
	if (!IsValid(entity) or !entity.IsPlayer or !entity:IsPlayer()) then return end

	local level = self:GetActiveLevel(entity)
	if (level < 3) then return end

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
