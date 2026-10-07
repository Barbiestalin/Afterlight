local PLUGIN = PLUGIN

util.AddNetworkString("AfterlightCelerityOwnerSound")

-- Файлы появятся позже; регистрируем пути заранее, чтобы клиенты скачали их
-- сразу после добавления.
resource.AddFile("sound/" .. ix.celerity.SOUND_USE)
resource.AddFile("sound/" .. ix.celerity.SOUND_LOOP)
resource.AddFile("sound/" .. ix.celerity.SOUND_LOOP_LEGACY)

-- Нуарная виньетка экрана и трейл «разорванного воздуха» (png + vmt с
-- параметрами трейла: вершинный цвет/альфа и аддитив).
resource.AddFile("materials/afterlight/disciplines/celerity/celerity_vignette.png")
resource.AddFile("materials/afterlight/disciplines/celerity/celerity_trail.vmt")
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
end

function PLUGIN:ClearCelerity(client)
	timer.Remove(TimerName(client))
	client:SetNW2Int("afterlightCelerityLevel", 0)
	client:SetNW2Float("afterlightCelerityEnd", 0)
	client:SetNW2Int("afterlightCelerityDodges", 0)
	RemoveTrail(client)
end

-- Шлейф «разорванного воздуха» (уровни 3+): собственная аддитивная текстура
-- через vmt с вершинной альфой (иначе трейл не рисуется), эмиссия с аттачмента
-- головы — из-за спины, а не из-под ног; на 4+ шире и плотнее.
local TRAIL_MATERIAL = "afterlight/disciplines/celerity/celerity_trail"

local function SpawnTrail(client, data)
	RemoveTrail(client)
	if ((data.trail or 0) <= 0) then return end
	local big = data.trail >= 2

	local attach = client.LookupAttachment and client:LookupAttachment("anim_attachment_head") or 0
	if (!attach or attach <= 0) then
		attach = 0
	end

	-- util.SpriteTrail существует только в server realm; сущность
	-- env_spritetrail реплицируется клиентам сама.
	local trail = util.SpriteTrail(client, attach, Color(205, 228, 248, big and 160 or 110), true,
		big and 30 or 18, big and 8 or 5, 0.9, 0.06, TRAIL_MATERIAL)
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
		if (!IsValid(weapon)) then continue end

		-- Темп ближнего боя: кулдауны сгорают быстрее. Ровно во столько же
		-- раз ускоряется и сама анимация (StartCommand), поэтому взмах
		-- успевает доиграть до следующей атаки — звуковые события и эффекты
		-- попаданий не теряются.
		if (data and data.attack > 1 and IsMeleeWeapon(weapon)) then
			ShrinkWeaponTimer(weapon, weapon.GetNextPrimaryFire, weapon.SetNextPrimaryFire, data.attack, dt, now)
			ShrinkWeaponTimer(weapon, weapon.GetNextSecondaryFire, weapon.SetNextSecondaryFire, data.attack, dt, now)
		end

		-- Перезарядка огнестрела: движок завершает её по таймеру следующего
		-- выстрела. Перезарядка начинается тапом R, поэтому в StartCommand
		-- ставится флаг; здесь таймер один раз сжимается в reload раз —
		-- пропорционально уровню дисциплины.
		if (weapon.afterlightReloadPending) then
			if (!data or data.reload <= 1) then
				weapon.afterlightReloadPending = nil
			else
				local nextAt = weapon.GetNextPrimaryFire and weapon:GetNextPrimaryFire() or 0
				if (nextAt > now + 0.05) then
					local remaining = nextAt - now
					weapon:SetNextPrimaryFire(now + remaining / data.reload)
					local nextSec = weapon.GetNextSecondaryFire and weapon:GetNextSecondaryFire() or 0
					if (nextSec > now) then
						weapon:SetNextSecondaryFire(now + (nextSec - now) / data.reload)
					end
					weapon.afterlightReloadPending = nil
					-- До конца исходной перезарядки новые не пересчитываем.
					weapon.afterlightReloadBlock = now + remaining
				end
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
	local now = CurTime()

	-- Тап перезарядки (клавиша зажата, магазин не полон) — помечаем, что
	-- таймер перезарядки нужно один раз сжать в Think.
	if (data and data.reload > 1 and weapon.GetMaxClip1 ~= nil and weapon:GetMaxClip1() > 0
		and cmd:KeyDown(IN_RELOAD) == true and weapon:Clip1() < weapon:GetMaxClip1()
		and !weapon.afterlightReloadPending
		and (!weapon.afterlightReloadBlock or weapon.afterlightReloadBlock < now)) then
		weapon.afterlightReloadPending = true
	end

	-- Ускорение анимации — ТОЛЬКО ближнего боя и ровно в меру темпа атаки:
	-- взмах проигрывается быстрее и успевает завершиться, события на месте.
	-- Огнестрел не трогаем: чужой playback rate ломал движковую перезарядку.
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
