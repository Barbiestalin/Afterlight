local PLUGIN = PLUGIN

util.AddNetworkString("AfterlightPotenceJumpFX")
util.AddNetworkString("AfterlightPotenceStatsChanged")

-- Файлы появятся позже (звуки из открытых источников); регистрируем пути
-- заранее, чтобы клиенты скачали их сразу после добавления.
resource.AddFile("sound/" .. ix.potence.SOUND_JUMP)
resource.AddFile("sound/" .. ix.potence.SOUND_HIT_LIGHT)
resource.AddFile("sound/" .. ix.potence.SOUND_HIT_HEAVY)

PLUGIN.soundAvailable = PLUGIN.soundAvailable or {}

local function SoundExists(path)
	local cached = PLUGIN.soundAvailable[path]
	if (cached == nil) then
		cached = file.Exists("sound/" .. path, "GAME") == true
		PLUGIN.soundAvailable[path] = cached
	end
	return cached
end

local function EmitIfAvailable(entity, path, volume)
	if (SoundExists(path)) then
		entity:EmitSound(path, volume or 80)
	end
end

local function TimerName(client)
	return "AfterlightPotence." .. (client:SteamID64() or client:EntIndex())
end

-- Активный уровень (0 — не активно). NW2-значения видны клиенту, поэтому
-- эффекты и лист характеризации обновляются без отдельных синхронизаций.
function PLUGIN:GetActiveLevel(client)
	local level = client:GetNW2Int("afterlightPotenceLevel", 0)
	if (level > 0 and client:GetNW2Float("afterlightPotenceEnd", 0) > CurTime()) then
		return level
	end
	return 0
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
	return true
end

-- Временный бонус к Силе: чарлист VTM Stats рисует его синими точками через
-- GetCharacterVTMStatBonus (тот же механизм, что у усиления крови).
function PLUGIN:GetCharacterVTMStatBonus(character, statID)
	if (statID != "strength") then return end
	local client = character and character:GetPlayer()
	if (!IsValid(client)) then return end
	local level = self:GetActiveLevel(client)
	if (level > 0) then
		return ix.potence.GetLevelData(level).strength
	end
end

local function IsMeleeHit(damageInfo)
	local inflictor = damageInfo:GetInflictor()
	if (IsValid(inflictor) and inflictor:GetClass() == "ix_hands") then return true end
	local damageType = damageInfo:GetDamageType()
	return bit.band(damageType, DMG_SLASH) != 0 or bit.band(damageType, DMG_CLUB) != 0
end

local DOOR_CLASSES = {prop_door_rotating = true, func_door = true, func_door_rotating = true}

-- Выбивание двери (уровни 4+): снимает замок и открывает даже запертую.
function PLUGIN:ForceDoorOpen(door)
	door:Fire("Unlock")
	door:Fire("Open")
	timer.Simple(0.25, function()
		if (IsValid(door)) then
			door:Fire("Open")
		end
	end)
end

function PLUGIN:EntityTakeDamage(victim, damageInfo)
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

	-- Звук удара поверх стандартного звука оружия: свой для 1-2 и для 3+.
	EmitIfAvailable(attacker, level >= 3 and ix.potence.SOUND_HIT_HEAVY or ix.potence.SOUND_HIT_LIGHT, 90)
end

-- Усиленный прыжок и эффекты взлёта: звук колебания воздуха и рябь (2+),
-- трещина в точке отталкивания (3+). Клиент рисует эффекты по этому сообщению.
function PLUGIN:PlayerJump(client)
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
		EmitIfAvailable(client, ix.potence.SOUND_JUMP, 80)
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
