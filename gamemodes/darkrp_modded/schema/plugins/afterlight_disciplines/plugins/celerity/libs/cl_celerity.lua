local PLUGIN = PLUGIN

-- Аура скорости: светлые штрихи по краям экрана на время действия (png с
-- запечённой прозрачностью), звук активации только у владельца и зацикленный
-- амбиент с плавными входом/выходом.
ix.celerity.fx = ix.celerity.fx or {alpha = 0, env = 0, target = 0, nextFlash = 0}

-- === Личные звуки (активация + амбиент) ===
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
local function PlayPotenceFile(path)
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
				PlayPotenceFile(fallback)
			end
		end)
	else
		PlayPotenceFile(fallback)
	end
end)

-- === Экранная аура скорости ===
local fxMaterial = nil
local fxTried = 0

local function GetFxMaterial(now)
	if (fxMaterial or now < fxTried) then
		return fxMaterial
	end

	fxTried = now + 5
	local path = "afterlight/disciplines/celerity/celerity_fx_a.png"
	local mat = file.Exists("materials/" .. path, "GAME") and Material(path) or nil
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

	local active = client:GetNW2Int("afterlightCelerityLevel", 0) > 0
		and client:GetNW2Float("afterlightCelerityEnd", 0) > CurTime()

	local dt = FrameTime()
	local now = RealTime()

	UpdateAmbience(active, now, dt)

	-- Плавные вход и выход ауры: 1 секунда в каждую сторону.
	local target = active and 1 or 0
	if (fx.alpha < target) then
		fx.alpha = math.min(fx.alpha + dt, 1)
	elseif (fx.alpha > target) then
		fx.alpha = math.max(fx.alpha - dt, 0)
	end
	if (fx.alpha <= 0.01) then return end

	-- Светлые штрихи то возникают, то прерываются; между ними аура дышит
	-- едва заметной постоянной основой.
	fx.target = fx.target * math.exp(-dt * 2.0)
	if (now >= fx.nextFlash) then
		fx.nextFlash = now + math.Rand(0.4, 1.2)
		fx.target = math.Rand(0.5, 1)
	end
	fx.env = fx.env + (fx.target - fx.env) * math.min(1, dt * 12)

	local pulse = 0.85 + 0.15 * math.sin(now * 2.6)
	local base = 0.45 + 0.2 * math.sin(now * 1.6 + 0.5)
	local strength = math.Clamp((fx.env * 0.9 + base) * pulse, 0, 1)
	if (strength <= 0.02) then return end

	local material = GetFxMaterial(now)
	if (material) then
		surface.SetDrawColor(255, 255, 255, math.Clamp(255 * fx.alpha * strength, 0, 255))
		surface.SetMaterial(material)
		surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
	end
end)
