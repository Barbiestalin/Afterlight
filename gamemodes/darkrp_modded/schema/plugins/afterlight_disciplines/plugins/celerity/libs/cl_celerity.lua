local PLUGIN = PLUGIN

-- libs включаются в алфавитном порядке: cl_celerity.lua идёт РАНЬШЕ
-- sh_celerity_levels.lua, поэтому таблицу создаём здесь сами.
ix.celerity = ix.celerity or {}

-- Нуарная аура скорости: мягкая тёмная виньетка по краям (мир для вампира
-- «замедляется и темнеет») плюс редкие тонкие штрихи ветра у краёв экрана.
-- Звук ветра — только при спринте (shift) на 3+ уровне. Звук активации —
-- только у владельца.
ix.celerity.fx = ix.celerity.fx or {alpha = 0, slashes = {}}

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

-- === Нуарная экранная аура ===
local VIGNETTE_PATH = "afterlight/disciplines/celerity/celerity_vignette.png"
local fxMaterial = nil
local fxTried = 0

local function GetFxMaterial(now)
	if (fxMaterial or now < fxTried) then
		return fxMaterial
	end

	fxTried = now + 5
	local mat = file.Exists("materials/" .. VIGNETTE_PATH, "GAME") and Material(VIGNETTE_PATH) or nil
	if (mat and mat:IsError()) then
		mat = nil
	end
	fxMaterial = mat
	return mat
end

hook.Add("HUDPaint", "AfterlightCelerityScreenFx", function()
	local client = LocalPlayer()
	if (!IsValid(client)) then return end
	local fx = ix.celerity.fx

	local level = client:GetNW2Int("afterlightCelerityLevel", 0)
	local active = level > 0 and client:GetNW2Float("afterlightCelerityEnd", 0) > CurTime()

	local dt = FrameTime()
	local now = RealTime()

	-- Ветер — только когда на 3+ уровне бежат спринтом (shift).
	UpdateAmbience(active and level >= 3 and client:KeyDown(IN_SPEED) == true, now, dt)

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

	-- Готическая виньетка: края экрана мягко темнеют, вампир видит мир
	-- «своим» зрением. Дышит очень медленно и едва заметно.
	local material = GetFxMaterial(now)
	if (material) then
		local breathe = 0.85 + 0.1 * math.sin(now * 1.3)
		surface.SetDrawColor(255, 255, 255, math.Clamp(255 * fx.alpha * breathe, 0, 255))
		surface.SetMaterial(material)
		surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
	end

	-- Редкие тонкие штрихи ветра у краёв: не чаще нескольких одновременно,
	-- живут доли секунды — скорость чувствуется, но экран не захламляется.
	fx.slashes = fx.slashes or {}
	if (active and #fx.slashes < 4 and math.Rand(0, 1) < dt * 2.5) then
		local horizontal = math.Rand(0, 1) < 0.7
		local w, h = ScrW(), ScrH()
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
