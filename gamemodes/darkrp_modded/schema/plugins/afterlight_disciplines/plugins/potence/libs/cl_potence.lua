local PLUGIN = PLUGIN

-- libs включаются в алфавитном порядке (ix.util.IncludeDir): на клиенте
-- cl_potence.lua идёт РАНЬШЕ sh_potence_levels.lua, поэтому таблицу создаём
-- здесь сами, а не полагаемся на порядок включения.
ix.potence = ix.potence or {}
ix.potence.cracks = ix.potence.cracks or {}

-- Локальный генератор случайности: форма трещины детерминирована точкой,
-- глобальный math.random не трогаем.
local function MakeRand(seed)
	local state = math.fmod(math.floor(math.abs(seed)), 2147483646) + 1
	return function()
		state = math.fmod(state * 16807, 2147483647)
		return (state - 1) / 2147483646
	end
end

net.Receive("AfterlightPotenceStatsChanged", function()
	hook.Run("AfterlightVTMTemporaryBonusesChanged", LocalPlayer():GetCharacter())
end)

-- Трейл воздушной ряби вешает СЕРВЕР (util.SpriteTrail — server realm,
-- на клиенте его нет — отсюда был краш). Клиент по этому сообщению
-- рисует только трещину (уровни 3+).
net.Receive("AfterlightPotenceJumpFX", function()
	net.ReadEntity()
	local position = net.ReadVector()
	local level = net.ReadUInt(3)
	if (level >= 3) then
		PLUGIN:AddCrack(position)
	end
end)

-- Пыль и каменные осколки, вздымающиеся из трещины: взрывной выброс
-- частиц в точке отталкивания.
local function EmitCrackDust(position)
	local emitter = ParticleEmitter(position)
	if (!emitter) then return end

	for i = 1, 12 do
		local angle = math.Rand(0, math.pi * 2)
		local radius = math.Rand(2, 16)
		local origin = position + Vector(math.cos(angle) * radius, math.sin(angle) * radius, 2)
		local material = i <= 7 and "particle/particle_smokegrenade"
			or "effects/fleck_cement" .. (i % 2 + 1)
		local particle = emitter:Add(material, origin)
		if (particle) then
			particle:SetVelocity(Vector(math.Rand(-35, 35), math.Rand(-35, 35), math.Rand(45, 120)))
			particle:SetDieTime(math.Rand(0.6, 1.4))
			particle:SetStartAlpha(math.Rand(60, 100))
			particle:SetEndAlpha(0)
			particle:SetStartSize(math.Rand(3, 6))
			particle:SetEndSize(math.Rand(10, 20))
			particle:SetColor(125, 115, 100)
			particle:SetGravity(Vector(0, 0, -70))
			particle:SetAirResistance(1)
		end
	end
	emitter:Finish()
end

-- Трещина в точке отталкивания: рваные лучи от эпицентра, живут
-- CRACK_LIFETIME секунд и тают в последнюю секунду.
function PLUGIN:AddCrack(position)
	local rand = MakeRand(position.x * 731 + position.y * 389 + position.z * 131)
	local branches = {}

	for _ = 1, 5 + math.floor(rand() * 3) do
		local angle = rand() * math.pi * 2
		local x, y = position.x, position.y
		local length = 12 + rand() * 14
		local width = 2.6 + rand() * 1.2
		local segments = {}

		for _ = 1, 3 + math.floor(rand() * 3) do
			angle = angle + (rand() - 0.5) * math.rad(56)
			local nx = x + math.cos(angle) * length
			local ny = y + math.sin(angle) * length
			segments[#segments + 1] = {x, y, nx, ny, width}
			x, y = nx, ny
			length = length * 0.72
			width = math.max(width * 0.7, 0.7)
		end
		branches[#branches + 1] = segments
	end

	table.insert(ix.potence.cracks, {branches = branches, z = position.z + 0.6, born = RealTime()})
	EmitCrackDust(position)
end

-- Лучи трещины рисуются балками в 3D-хуке: surface.DrawPoly работает ТОЛЬКО
-- в 2D-хуках, поэтому для 3D берём render.DrawBeam.
local crackMaterial = Material("trails/smoke.vmt")

local function DrawCrack(crack, alpha)
	local color = Color(14, 11, 10, alpha)
	for _, segments in ipairs(crack.branches) do
		for _, segment in ipairs(segments) do
			render.DrawBeam(
				Vector(segment[1], segment[2], crack.z),
				Vector(segment[3], segment[4], crack.z),
				segment[5], 0, 1, color)
		end
	end
end

hook.Add("PostDrawTranslucentRenderables", "AfterlightPotenceCracks", function()
	local cracks = ix.potence.cracks
	if (#cracks == 0) then return end

	local now = RealTime()
	for index = #cracks, 1, -1 do
		if (now - cracks[index].born > ix.potence.CRACK_LIFETIME) then
			table.remove(cracks, index)
		end
	end
	if (#cracks == 0) then return end

	render.SetMaterial(crackMaterial)
	for _, crack in ipairs(cracks) do
		local remaining = ix.potence.CRACK_LIFETIME - (now - crack.born)
		DrawCrack(crack, 235 * math.Clamp(remaining, 0, 1))
	end
end)
