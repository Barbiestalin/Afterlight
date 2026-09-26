local PLUGIN = PLUGIN

ix.potence.cracks = ix.potence.cracks or {}
ix.potence.trails = ix.potence.trails or {}

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

net.Receive("AfterlightPotenceJumpFX", function()
	local client = net.ReadEntity()
	local position = net.ReadVector()
	local level = net.ReadUInt(3)
	if (!IsValid(client) or level == 0) then return end

	if (level >= 2) then
		PLUGIN:AttachJumpTrail(client)
	end
	if (level >= 3) then
		PLUGIN:AddCrack(position)
	end
end)

-- Воздушная рябь за персонажем при усиленном прыжке: короткий дымчатый трейл.
function PLUGIN:AttachJumpTrail(client)
	local old = self.trails[client]
	if (IsValid(old)) then old:Remove() end

	local trail = util.SpriteTrail(client, 0, Color(215, 220, 230, 55), false, 12, 1, 1.4, 0.15,
		"trails/smoke.vmt")
	self.trails[client] = trail
	timer.Simple(1.8, function()
		if (IsValid(trail)) then trail:Remove() end
	end)
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

	table.insert(self.cracks, {branches = branches, z = position.z + 0.6, born = RealTime()})
end

local function DrawCrack(crack, alpha)
	surface.SetDrawColor(12, 10, 10, alpha)
	for _, segments in ipairs(crack.branches) do
		for _, segment in ipairs(segments) do
			local x1, y1, x2, y2, width = segment[1], segment[2], segment[3], segment[4], segment[5]
			local dx, dy = x2 - x1, y2 - y1
			local length = math.sqrt(dx * dx + dy * dy)
			if (length > 0.01) then
				local px, py = (-dy / length) * width * 0.5, (dx / length) * width * 0.5
				surface.DrawPoly({
					{x = x1 + px, y = y1 + py, z = crack.z},
					{x = x2 + px, y = y2 + py, z = crack.z},
					{x = x2 - px, y = y2 - py, z = crack.z},
					{x = x1 - px, y = y1 - py, z = crack.z}
				})
			end
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

	cam.Start3D()
	for _, crack in ipairs(cracks) do
		local remaining = ix.potence.CRACK_LIFETIME - (now - crack.born)
		local alpha = 235 * math.Clamp(remaining, 0, 1)
		DrawCrack(crack, alpha)
	end
	cam.End3D()
end)
