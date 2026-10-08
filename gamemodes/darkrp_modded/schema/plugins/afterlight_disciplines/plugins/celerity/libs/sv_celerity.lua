local PLUGIN = PLUGIN

util.AddNetworkString("AfterlightCelerityOwnerSound")

-- Файлы появятся позже; регистрируем пути заранее, чтобы клиенты скачали их
-- сразу после добавления.
resource.AddFile("sound/" .. ix.celerity.SOUND_USE)
resource.AddFile("sound/" .. ix.celerity.SOUND_LOOP)
resource.AddFile("sound/" .. ix.celerity.SOUND_LOOP_LEGACY)

-- Оверлеи экранной ауры (прозрачность запечена в png).
resource.AddFile("materials/afterlight/disciplines/celerity/celerity_fx_a.png")
resource.AddFile("materials/afterlight/disciplines/celerity/celerity_fx_b.png")

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
	-- Трейл снимается, флаг спринта гасится — ни ветер, ни шлейф не
	-- переживают окончание дисциплины.
	local trail = client.afterlightCelerityTrail
	if (trail) then
		for _, ent in ipairs({trail.anchor, trail.bright, trail.haze}) do
			if (IsValid(ent)) then
				ent:Remove()
			end
		end
		client.afterlightCelerityTrail = nil
	end
	client:SetNW2Bool("afterlightCeleritySprint", false)
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
	-- Модификаторы оружия применяются в Think (туда же попадает respawn и
	-- смена оружия). Звук использования слышит ТОЛЬКО активировавший.
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

-- Модификаторы активного оружия:
--  * у Lua-милее честно уменьшается Primary.Delay — следующий удар
--    разрешается раньше, а анимация (включая внешнюю) успевает доиграть,
--    потому что звук/события привязаны к самому факту атаки;
--  * playback rate оружия: милее размахивает быстрее, огнестрел быстрее
--    крутит анимацию перезарядки (rate ставится ДО начала перезарядки,
--    поэтому движок сразу считает её укороченной);
--  * без данных всё возвращается к исходному.
local function ApplyWeaponMods(weapon, data)
	local isMelee = IsMeleeWeapon(weapon)

	if (weapon.Primary and isnumber(weapon.Primary.Delay)) then
		if (!weapon.afterlightOrigDelay) then
			weapon.afterlightOrigDelay = weapon.Primary.Delay
		end
		local want = weapon.afterlightOrigDelay
		if (data and isMelee and data.attack > 1) then
			want = want / data.attack
		end
		if (weapon.Primary.Delay != want) then
			weapon.Primary.Delay = want
		end
	end

	local rate = 1
	if (data) then
		if (isMelee) then
			rate = data.attack
		elseif (weapon.GetMaxClip1 ~= nil and weapon:GetMaxClip1() > 0) then
			rate = data.reload
		end
	end
	if (weapon.SetPlaybackRate and weapon.afterlightPlaybackRate != rate) then
		weapon:SetPlaybackRate(rate)
		weapon.afterlightPlaybackRate = rate
	end

	-- Аддоны (TFA/M9K и подобные) держат время перезарядки в собственных
	-- полях — честно делим и их, восстанавливая после окончания.
	for _, field in ipairs({"ReloadTime", "reloadtime", "reloadTime", "ReloadDelay", "reloadDelay", "LoadDelay"}) do
		if (isnumber(weapon[field])) then
			local origKey = "afterlightOrig_" .. field
			if (!weapon[origKey]) then
				weapon[origKey] = weapon[field]
			end
			local want = weapon[origKey]
			if (data and data.reload > 1) then
				want = want / data.reload
			end
			if (weapon[field] != want) then
				weapon[field] = want
			end
		end
	end
end

-- Кулдаун оружия тратится в mult раз быстрее реального времени — для оружия
-- без Primary.Delay (C++ милее), чтобы темп всё равно рос.
local function ShrinkWeaponTimer(weapon, getter, setter, mult, dt, now)
	local nextAt = getter(weapon)
	if (nextAt and nextAt > now) then
		local remaining = math.max(nextAt - now - (mult - 1) * dt, 0)
		setter(weapon, now + remaining)
	end
end

-- Спринт считает СЕРВЕР по авторитетной скорости: GetWalkSpeed на
-- сервере точный (включая наше ускорение), поэтому порог walk*1.15 отделяет
-- именно хеликсовский спринт от ходьбы. Клиент лишь читает NW2-флаг — ветер
-- и трейл живут строго по спринту, а не по факту активации дисциплины.
local function IsSprinting(client, level, data)
	return data ~= nil and level >= 3
		and client:GetVelocity():Length2D() > client:GetWalkSpeed() * 1.15
end

-- Трейл — штатная «труба» (trails/tube.vmt), КОРОТКАЯ и ванильная по поведению:
-- ленты рождаются только когда якорь движется и ТАЮТ САМИ (~0.2с), поэтому
-- шлейф плавно идёт за персонажем и затухает. Сущности трейла живут всё время
-- дисциплины и НЕ пересоздаются при спринте — никакого «удалился и заново».
-- Якорь — невидимая сущность на кости позвоночника: шлейф исходит из спины,
-- а не из ног. Схема вызова SpriteTrail — как у штатных трейлов (attach 0).
local function UpdateSpeedTrail(client, level, data)
	local want = data ~= nil and level >= 3 and (data.trail or 0) > 0
	local current = client.afterlightCelerityTrail

	if (!want) then
		if (current) then
			for _, ent in ipairs({current.anchor, current.bright, current.haze}) do
				if (IsValid(ent)) then
					ent:Remove()
				end
			end
			client.afterlightCelerityTrail = nil
		end
		return
	end

	if (current and IsValid(current.anchor) and current.level == level) then return end
	if (current) then
		for _, ent in ipairs({current.anchor, current.bright, current.haze}) do
			if (IsValid(ent)) then
				ent:Remove()
			end
		end
	end

	local bone = client.LookupBone and client:LookupBone("ValveBiped.Bip01_Spine2") or nil
	local anchor = ents.Create("prop_dynamic")
	anchor:SetModel("models/props_junk/watermelon01_chunk01.mdl")
	anchor:AddEffects(EF_NODRAW)
	if (bone and bone > 0) then
		anchor:SetParent(client, bone)
	else
		anchor:SetParent(client)
	end
	anchor:SetLocalPos(Vector(0, 0, 0))
	anchor:Spawn()

	local scale = 1 + (level - 3) * 0.45 -- 4-5 уровни: крупный шлейф по ТЗ
	local bright = util.SpriteTrail(anchor, 0, Color(175, 210, 240, 90), true,
		0.2, 4 * scale, 1, 0.125, "trails/tube.vmt")
	local haze = util.SpriteTrail(anchor, 0, Color(140, 180, 220, 40), true,
		0.16, 9 * scale, 2, 0.125, "trails/tube.vmt")
	client.afterlightCelerityTrail = {anchor = anchor, bright = bright, haze = haze, level = level}
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

		-- Вся анимация игрока снаружи идёт быстрее — внешне персонаж
		-- двигается и бьёт как ускоренный, события не теряются.
		local wantRate = data and data.attack or 1
		if (client.afterlightRate != wantRate) then
			client:SetPlaybackRate(wantRate)
			client.afterlightRate = wantRate
		end

		local sprinting = IsSprinting(client, level, data)
		if (client:GetNW2Bool("afterlightCeleritySprint", false) ~= sprinting) then
			client:SetNW2Bool("afterlightCeleritySprint", sprinting)
		end
		UpdateSpeedTrail(client, level, data)

		local weapon = client:GetActiveWeapon()
		if (!IsValid(weapon)) then continue end

		ApplyWeaponMods(weapon, data)

		-- C++ милее без Primary.Delay: кулдауны сгорают быстрее.
		if (data and data.attack > 1 and IsMeleeWeapon(weapon)
			and !(weapon.Primary and isnumber(weapon.Primary.Delay))) then
			ShrinkWeaponTimer(weapon, weapon.GetNextPrimaryFire, weapon.SetNextPrimaryFire, data.attack, dt, now)
			ShrinkWeaponTimer(weapon, weapon.GetNextSecondaryFire, weapon.SetNextSecondaryFire, data.attack, dt, now)
		end

		-- Перезарядка огнестрела: тап R открывает окно, в котором таймер
		-- следующего выстрела (похожий на перезарядку, >0.4с) непрерывно
		-- сжимается в reload раз — пропорционально уровню.
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
