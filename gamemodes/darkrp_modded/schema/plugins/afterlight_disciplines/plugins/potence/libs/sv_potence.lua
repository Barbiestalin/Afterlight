local PLUGIN = PLUGIN

util.AddNetworkString("AfterlightPotenceJumpFX")
util.AddNetworkString("AfterlightPotenceStatsChanged")
util.AddNetworkString("AfterlightPotenceOwnerSound")
util.AddNetworkString("AfterlightPotenceAreaSound")

-- Файлы появятся позже (звуки из открытых источников); регистрируем пути
-- заранее, чтобы клиенты скачали их сразу после добавления.
resource.AddFile("sound/" .. ix.potence.SOUND_USE)
resource.AddFile("sound/" .. ix.potence.SOUND_PUNCH)
resource.AddFile("sound/" .. ix.potence.SOUND_DOOR)
resource.AddFile("sound/" .. ix.potence.SOUND_JUMP)
resource.AddFile("sound/" .. ix.potence.SOUND_CRACK)

-- Экранная аура Могущества: оверлеи красных молний (прозрачность в png).
resource.AddFile("materials/afterlight/disciplines/potence/potence_fx_a.png")
resource.AddFile("materials/afterlight/disciplines/potence/potence_fx_b.png")
resource.AddFile("materials/afterlight/disciplines/potence/potence_fx_c.png")
resource.AddFile("sound/" .. ix.potence.SOUND_LOOP)
resource.AddFile("sound/" .. ix.potence.SOUND_LOOP_LEGACY)

PLUGIN.soundAvailable = PLUGIN.soundAvailable or {}

local function SoundExists(path)
	local cached = PLUGIN.soundAvailable[path]
	if (cached == nil) then
		cached = file.Exists("sound/" .. path, "GAME") == true
		PLUGIN.soundAvailable[path] = cached
	end
	return cached
end

-- Своё звучание, а пока файла нет — стоковый фолбэк: способность слышна
-- сразу после установки. Радиус 80 единиц ≈ 2 метра.
local function EmitWithFallback(entity, customPath, fallbackPath, volume)
	if (SoundExists(customPath)) then
		entity:EmitSound(customPath, volume or 80)
	elseif (fallbackPath) then
		entity:EmitSound(fallbackPath, volume or 80)
	end
end

-- Звук удара шлётся клиентам в радиусе и играется каждым локально через
-- PlayFile на полной громкости: серверный EmitSound режет громкость заметно тише,
-- из-за чего удар было «либо не слышно, либо очень плохо».
function PLUGIN:BroadcastPotenceSound(origin, customPath, fallbackPath, radius)
	local listeners = {}
	for _, listener in ipairs(player.GetAll()) do
		if (IsValid(listener) and listener:GetPos():Distance(origin:GetPos()) <= radius) then
			listeners[#listeners + 1] = listener
		end
	end
	if (#listeners == 0) then return end
	net.Start("AfterlightPotenceAreaSound")
		net.WriteString(customPath)
		net.WriteString(fallbackPath)
	net.Send(listeners)
end

local function TimerName(client)
	return "AfterlightPotence." .. (client:SteamID64() or client:EntIndex())
end

function PLUGIN:NotifyStats(character)
	local client = character and character:GetPlayer()
	if (IsValid(client)) then
		net.Start("AfterlightPotenceStatsChanged")
		net.Send(client)
	end
end

function PLUGIN:ClearPotence(client)
	timer.Remove(TimerName(client))
	client:SetNW2Int("afterlightPotenceLevel", 0)
	client:SetNW2Float("afterlightPotenceEnd", 0)
	self:NotifyStats(client:GetCharacter())
end

-- Активация уровня: повторная активация разрешена и сбрасывает таймер,
-- витэ шлюз интерфейса списывает при каждой активации.
function PLUGIN:ActivatePotence(client, character, level)
	local data = ix.potence.GetLevelData(level)
	if (!data or !IsValid(client)) then return false, "notAllowed" end

	client:SetNW2Int("afterlightPotenceLevel", level)
	client:SetNW2Float("afterlightPotenceEnd", CurTime() + data.duration)
	timer.Create(TimerName(client), data.duration, 1, function()
		if (IsValid(client)) then
			self:ClearPotence(client)
		end
	end)
	self:NotifyStats(character)
	-- Звук использования слышит ТОЛЬКО сам активировавший: сервер шлёт
	-- персональный net, клиент играет его локально.
	net.Start("AfterlightPotenceOwnerSound")
		net.WriteString(ix.potence.SOUND_USE)
		net.WriteString(ix.potence.SOUND_FALLBACKS.activate)
	net.Send(client)
	return true
end

local function IsMeleeHit(damageInfo)
	local inflictor = damageInfo:GetInflictor()
	if (IsValid(inflictor) and inflictor:GetClass() == "ix_hands") then return true end
	local damageType = damageInfo:GetDamageType()
	return bit.band(damageType, DMG_SLASH) != 0 or bit.band(damageType, DMG_CLUB) != 0
end

local DOOR_CLASSES = {prop_door_rotating = true, func_door = true, func_door_rotating = true}

-- Выбивание двери (уровни 4+): снимает замок и открывает даже запертую,
-- включая парную створку (как ix_keys в Helix: unlock/open + партнёр).
function PLUGIN:ForceDoorOpen(door)
	door:Fire("unlock")
	door:Fire("open")
	local partner = door.GetDoorPartner and door:GetDoorPartner() or nil
	if (IsValid(partner)) then
		partner:Fire("unlock")
		partner:Fire("open")
	end
	if (door.IsLocked) then
		door.IsLocked = nil
	end
	timer.Simple(0.25, function()
		if (IsValid(door)) then
			door:Fire("open")
		end
	end)
end

-- Двери на серверах (DarkRP/Helix) обычно неуязвимы к урону, поэтому
-- EntityTakeDamage по ним не стреляет. Выбивание ловим по самой атаке:
-- пока активен уровень 4+, удар (IN_ATTACK/IN_ATTACK2) по двери выбивает её.
function PLUGIN:StartCommand(client, cmd)
	if (self:GetActiveLevel(client) < 4) then return end
	if (!cmd:KeyDown(IN_ATTACK) and !cmd:KeyDown(IN_ATTACK2)) then return end
	if ((client.afterlightPotenceDoorNext or 0) > CurTime()) then return end
	client.afterlightPotenceDoorNext = CurTime() + 0.5

	local data = {start = client:GetShootPos(), filter = client}
	data.endpos = data.start + client:GetAimVector() * 100
	local trace = util.TraceLine(data)
	local entity = trace.Entity
	if (IsValid(entity) and (DOOR_CLASSES[entity:GetClass()] or (entity.IsDoor and entity:IsDoor()))) then
		self:ForceDoorOpen(entity)
		EmitWithFallback(client, ix.potence.SOUND_DOOR, ix.potence.SOUND_FALLBACKS.doorKick, 90)
	end
end

function PLUGIN:EntityTakeDamage(victim, damageInfo)
	-- На время действия Могущества (2+) урон от падения не наносится.
	if (victim:IsPlayer() and damageInfo:IsDamageType(DMG_FALL) and self:GetActiveLevel(victim) >= 2) then
		damageInfo:SetDamage(0)
		return
	end

	local attacker = damageInfo:GetAttacker()
	if (!IsValid(attacker) or !attacker:IsPlayer() or attacker == victim) then return end
	local level = self:GetActiveLevel(attacker)
	if (level == 0 or !IsMeleeHit(damageInfo)) then return end
	local data = ix.potence.GetLevelData(level)

	if (data.doors and IsValid(victim) and DOOR_CLASSES[victim:GetClass()]) then
		self:ForceDoorOpen(victim)
	end

	damageInfo:SetDamage(damageInfo:GetDamage() + data.damage)

	if (victim:IsPlayer()) then
		local direction = victim:GetPos() - attacker:GetPos()
		direction.z = 0
		if (direction:LengthSqr() < 1) then
			direction = attacker:GetAimVector()
			direction.z = 0
		end
		direction:Normalize()
		victim:SetVelocity(direction * data.knockback)
	end

	-- Особый звук удара поверх стандартного звука оружия (с уровня 2).
	if (level >= 2) then
		self:BroadcastPotenceSound(attacker, ix.potence.SOUND_PUNCH,
			level >= 3 and ix.potence.SOUND_FALLBACKS.hitHeavy or ix.potence.SOUND_FALLBACKS.hitLight,
			ix.potence.PUNCH_RADIUS)
	end
end

-- Усиленный прыжок и эффекты взлёта: звук колебания воздуха и рябь (2+),
-- трещина в точке отталкивания (3+). Клиент рисует эффекты по этому сообщению.
-- Хук именно OnPlayerJump: GM:PlayerJump в GMod не существует.
function PLUGIN:OnPlayerJump(client)
	local level = self:GetActiveLevel(client)
	if (level == 0) then return end
	local data = ix.potence.GetLevelData(level)

	if (data.jumpMeters > 0) then
		local gravity = GetConVarNumber("sv_gravity") or 600
		local target = ix.potence.JumpVelocity(data.jumpMeters, gravity)
		local current = client:GetVelocity()
		client:SetVelocity(Vector(0, 0, target - current.z))
	end

	net.Start("AfterlightPotenceJumpFX")
		net.WriteEntity(client)
		net.WriteVector(client:GetPos())
		net.WriteUInt(level, 3)
	net.SendPVS(client:GetPos())

	if (level >= 2) then
		-- Колебание воздуха слышно и самому, и игрокам в радиусе ~2 метров.
		EmitWithFallback(client, ix.potence.SOUND_JUMP, ix.potence.SOUND_FALLBACKS.jump, 80)

		-- util.SpriteTrail существует только в server realm; сущность
		-- env_spritetrail реплицируется клиентам сама. Трейл выключается
		-- через 2 секунды после появления.
		local trail = util.SpriteTrail(client, 0, Color(205, 212, 224, 60), false,
			12, 1, 1.2, 0.04, "trails/smoke.vmt")
		if (IsValid(trail)) then
			timer.Simple(2, function()
				if (IsValid(trail)) then
					trail:Remove()
				end
			end)
		end
	end

	if (level >= 3) then
		EmitWithFallback(client, ix.potence.SOUND_CRACK, ix.potence.SOUND_FALLBACKS.crack, 80)
	end
end

function PLUGIN:PlayerLoadedCharacter(client)
	timer.Remove(TimerName(client))
	client:SetNW2Int("afterlightPotenceLevel", 0)
	client:SetNW2Float("afterlightPotenceEnd", 0)
end

function PLUGIN:PlayerDeath(client)
	self:ClearPotence(client)
end

function PLUGIN:PlayerDisconnected(client)
	timer.Remove(TimerName(client))
end

function PLUGIN:OnVampirismRemoved(actor, target)
	if (IsValid(target)) then
		self:ClearPotence(target)
	end
end
