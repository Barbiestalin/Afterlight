local PLUGIN = PLUGIN

-- libs включаются в алфавитном порядке: cl_celerity.lua идёт РАНЬШЕ
-- sh_celerity_levels.lua, поэтому таблицу создаём здесь сами.
ix.celerity = ix.celerity or {}

-- Нуарная аура скорости: процедурная тёмная виньетка + два наложенных слоя
-- светлых штрихов (png с запечённой прозрачностью), живущих своими вспышками,
-- редкие ветровые штрихи и трейл «разорванного воздуха» частицами — только
-- во время спринта (shift) на 3+. Звук ветра — тоже только при спринте.
ix.celerity.fx = ix.celerity.fx or {alpha = 0, slashes = {}, layers = {}}

-- === Личные звуки (активация + ветер при спринте) ===
local ambient = {channel = nil, loading = false, volume = 0, state = "off", startAt = 0, path = nil, pathTry = 0}
ix.celerity.fx.amb = ambient

local function GetLoopPath(now)
	if (ambient.path or now < ambient.pathTry) then
		return ambient.path
	end

	ambient.pathTry = now + 5
	for _, candidate in ipairs({ix.celerity.SOUND_LOOP, ix.celerity.SOUND_LOOP_LEGACY}) do
		if (candidate and file.Exists("sound/" .. candidate, "GAME")) then
			ambient.path = candidate
			break
		end
	end
	return ambient.path
end

local function UpdateAmbience(active, now, dt)
	if (active and ambient.state == "off") then
		ambient.state = "wait"
		ambient.startAt = now + (ix.celerity.AMBIENT_DELAY or 1.2)
	elseif (!active and ambient.state == "wait") then
		ambient.state = "off"
	elseif (!active and (ambient.state == "in" or ambient.state == "out")) then
		ambient.state = "out"
	elseif (active and ambient.state == "out") then
		ambient.state = "in"
	end

	if (ambient.state == "wait" and now >= ambient.startAt) then
		ambient.state = "in"
	end

	if ((ambient.state == "in" or ambient.state == "out") and !ambient.channel and !ambient.loading) then
		local path = GetLoopPath(now)
		if (path) then
			ambient.loading = true
			sound.PlayFile("sound/" .. path, "loop noblock noplay", function(channel)
				ambient.loading = false
				if (IsValid(channel)) then
					ambient.channel = channel
					channel:SetVolume(0)
					channel:Play()
				end
			end)
		end
	end

	local channel = ambient.channel
	if (!channel) then return end

	if (ambient.state == "in") then
		ambient.volume = math.min(ambient.volume + dt / (ix.celerity.AMBIENT_FADE or 1), 1)
	elseif (ambient.state == "out") then
		ambient.volume = math.max(ambient.volume - dt / (ix.celerity.AMBIENT_FADE or 1), 0)
	end

	if (ambient.volume <= 0 and ambient.state == "out") then
		channel:Stop()
		ambient.channel = nil
		ambient.state = "off"
		return
	end

	channel:SetVolume(ambient.volume * (ix.celerity.AMBIENT_VOLUME or 0.7))
end

-- Звук активации слышит только владелец; PlayFile терпим к mp3, а при ошибке
-- декодирования играет фолбэк вместо тишины.
local function PlayCelerityFile(path)
	sound.PlayFile("sound/" .. path, "noplay noblock", function(channel)
		if (IsValid(channel)) then
			channel:SetVolume(ix.celerity.SOUND_VOLUME or 1)
			channel:Play()
		end
	end)
end

net.Receive("AfterlightCelerityOwnerSound", function()
	local custom = net.ReadString()
	local fallback = net.ReadString()
	if (file.Exists("sound/" .. custom, "GAME")) then
		sound.PlayFile("sound/" .. custom, "noplay noblock", function(channel)
			if (IsValid(channel)) then
				channel:SetVolume(ix.celerity.SOUND_VOLUME or 1)
				channel:Play()
			else
				PlayCelerityFile(fallback)
			end
		end)
	else
		PlayCelerityFile(fallback)
	end
end)

-- === Трейл «разорванного воздуха» частицами (только спринт на 3+) ===
-- 3D-рендеру нужны штатные материалы (сырой png в частицах даёт error-
-- «шахматку»), поэтому берём стоковые «пар/свечение» и красим в ледяной
-- оттенок — выглядит как рваный воздух за спиной.
-- trails/smoke и particle_smokegrenade — гарантированно существующие материалы
-- (проверены боем на трейле Могущества), в ледяном тоне дают «рваный воздух».
local TRAIL_MATERIALS = {"trails/smoke", "particle/particle_smokegrenade"}
local trailEmitter = nil
local lastTrailSpawn = 0

local function UpdateTrail(client, active, level, sprinting, now)
	if (!active or level < 3 or !sprinting) then return end
	if (client:GetVelocity():Length2D() < 80) then return end
	if (now < lastTrailSpawn) then return end
	lastTrailSpawn = now + 0.035

	trailEmitter = trailEmitter or ParticleEmitter(client:GetPos())
	if (!trailEmitter) then return end

	local big = level >= 4
	local bone = client.LookupBone and client:LookupBone("ValveBiped.Bip01_Spine2") or nil
	local origin = (bone and bone > 0 and client:GetBonePosition(bone))
		or (client:GetPos() + Vector(0, 0, 50))

	local material = TRAIL_MATERIALS[math.random(1, #TRAIL_MATERIALS)]
	local particle = trailEmitter:Add(material,
		origin + Vector(math.Rand(-3, 3), math.Rand(-3, 3), math.Rand(-2, 4)))
	if (!particle) then return end

	particle:SetDieTime(math.Rand(0.4, 0.8))
	particle:SetStartAlpha(big and 90 or 60)
	particle:SetEndAlpha(0)
	particle:SetStartSize(big and 8 or 5)
	particle:SetEndSize(big and 30 or 20)
	particle:SetColor(190, 215, 235)
	particle:SetVelocity(client:GetVelocity() * -0.12 + Vector(math.Rand(-8, 8), math.Rand(-8, 8), math.Rand(0, 14)))
	particle:SetGravity(Vector(0, 0, 26))
	particle:SetRoll(math.Rand(0, 6.28))
	particle:SetRollDelta(math.Rand(-1.5, 1.5))
end

-- === Нуарная экранная аура ===
local LAYER_PATHS = {
	"afterlight/disciplines/celerity/celerity_fx_a.png",
	"afterlight/disciplines/celerity/celerity_fx_b.png"
}
local layerMaterials = {}

local function GetLayerMaterial(index, now)
	local entry = layerMaterials[index]
	if (entry and (entry.mat or now < entry.nextTry)) then
		return entry.mat
	end

	local mat = file.Exists("materials/" .. LAYER_PATHS[index], "GAME") and Material(LAYER_PATHS[index]) or nil
	if (mat and mat:IsError()) then
		mat = nil
	end
	layerMaterials[index] = {mat = mat, nextTry = now + 5}
	return mat
end

local BANDS = 26

hook.Add("HUDPaint", "AfterlightCelerityScreenFx", function()
	local client = LocalPlayer()
	if (!IsValid(client)) then return end
	local fx = ix.celerity.fx

	local level = client:GetNW2Int("afterlightCelerityLevel", 0)
	local active = level > 0 and client:GetNW2Float("afterlightCelerityEnd", 0) > CurTime()
	-- Entity:KeyDown на клиенте не работает — читаем локальную клавиатуру.
	-- Спринт определяем по факту быстрого движения (работает при любом бинде
	-- Helix): скорость выше ходьбы * 1.15 — значит, бегут спринтом.
	local sprinting = client:GetVelocity():Length2D() > client:GetWalkSpeed() * 1.15

	local dt = FrameTime()
	local now = RealTime()

	-- Ветер — только когда на 3+ уровне бегут спринтом.
	UpdateAmbience(active and level >= 3 and sprinting, now, dt)
	UpdateTrail(client, active, level, sprinting, now)

	-- Плавные вход и выход ауры: 1 секунда в каждую сторону.
	local target = active and 1 or 0
	if (fx.alpha < target) then
		fx.alpha = math.min(fx.alpha + dt, 1)
	elseif (fx.alpha > target) then
		fx.alpha = math.max(fx.alpha - dt, 0)
	end
	if (fx.alpha <= 0.01) then
		fx.slashes = {}
		return
	end

	local w, h = ScrW(), ScrH()

	-- 1) Готическая виньетка: края экрана мягко темнеют полосами градиента —
	-- вампир видит мир «своим» зрением. Процедурно, без текстур.
	local band = math.min(w, h) * 0.16
	local step = band / BANDS
	local breathe = 0.85 + 0.1 * math.sin(now * 1.3)
	for i = 1, BANDS do
		local t = (i - 0.5) / BANDS
		local alpha = math.Clamp(150 * (1 - t) * (1 - t) * breathe * fx.alpha, 0, 255)
		if (alpha < 1) then break end
		local inset = (i - 1) * step
		surface.SetDrawColor(2, 3, 5, alpha)
		surface.DrawRect(inset, inset, w - inset * 2, step)
		surface.DrawRect(inset, h - inset - step, w - inset * 2, step)
		surface.DrawRect(inset, inset + step, step, h - (inset + step) * 2)
		surface.DrawRect(w - inset - step, inset + step, step, h - (inset + step) * 2)
	end

	-- 2) Два наложенных слоя светлых штрихов: каждый живёт своей вспышкой —
	-- слои мерцают в противофазе, экран «анимируется» скоростью.
	for index = 1, #LAYER_PATHS do
		local layer = fx.layers[index]
		if (!layer) then
			layer = {env = 0, target = 0, next = 0}
			fx.layers[index] = layer
		end

		layer.target = layer.target * math.exp(-dt * 2.0)
		if (now >= layer.next) then
			layer.next = now + math.Rand(0.35, 1.1)
			layer.target = math.Rand(0.45, 1)
		end
		layer.env = layer.env + (layer.target - layer.env) * math.min(1, dt * 12)

		local phase = 0.7 + 0.3 * math.sin(now * (1.9 + index * 0.7) + index * 2.1)
		local strength = math.Clamp(layer.env * phase * 0.8 * fx.alpha, 0, 1)
		local material = GetLayerMaterial(index, now)
		if (material and strength > 0.03) then
			surface.SetDrawColor(255, 255, 255, math.Clamp(255 * strength, 0, 255))
			surface.SetMaterial(material)
			surface.DrawTexturedRect(0, 0, w, h)
		end
	end

	-- 3) Редкие тонкие штрихи ветра у краёв: не больше четырёх одновременно,
	-- живут доли секунды — скорость чувствуется, экран не захламляется.
	fx.slashes = fx.slashes or {}
	if (active and #fx.slashes < 4 and math.Rand(0, 1) < dt * 2.5) then
		local horizontal = math.Rand(0, 1) < 0.7
		local slash = {life = 0, max = math.Rand(0.18, 0.4), horizontal = horizontal}
		if (horizontal) then
			slash.len = math.Rand(90, 260)
			slash.x = math.Rand(0, w - slash.len)
			slash.y = math.Rand(0, 1) < 0.5 and math.Rand(0, h * 0.22) or math.Rand(h * 0.78, h)
		else
			slash.len = math.Rand(70, 180)
			slash.x = math.Rand(0, 1) < 0.5 and math.Rand(0, w * 0.18) or math.Rand(w * 0.82, w)
			slash.y = math.Rand(0, h - slash.len)
		end
		fx.slashes[#fx.slashes + 1] = slash
	end

	for index = #fx.slashes, 1, -1 do
		local slash = fx.slashes[index]
		slash.life = slash.life + dt
		if (slash.life >= slash.max) then
			table.remove(fx.slashes, index)
		else
			local k = math.sin(math.pi * slash.life / slash.max)
			surface.SetDrawColor(205, 222, 238, math.Clamp(70 * k * fx.alpha, 0, 255))
			if (slash.horizontal) then
				surface.DrawLine(slash.x, slash.y, slash.x + slash.len, slash.y)
			else
				surface.DrawLine(slash.x, slash.y, slash.x, slash.y + slash.len)
			end
		end
	end
end)
