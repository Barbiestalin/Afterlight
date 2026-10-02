local PLUGIN = PLUGIN

-- Кровавая аура Могущества по краям экрана (эстетика VTM Bloodlines):
-- три слоя красных молний (прозрачность запечена в png), у каждого своя
-- плавная огибающая вспышек, третий слой — «дышащая» база ауры; общая
-- пульсация и плавные появление/затухание за 1 секунду.
-- Там же — амбиент дисциплины: зацикленный звук на всё время действия,
-- плавно входящий после звука активации и плавно затухающий в конце.
ix.potence.fx = ix.potence.fx or {alpha = 0, layers = {}}

local LAYERS = {"potence_fx_a", "potence_fx_b", "potence_fx_c"}
local materials = {}

-- Прозрачность запечена в сам PNG (чёрный = прозрачный), поэтому vmt не
-- нужен: стандартный png подхватывается Material() напрямую. Если файла
-- ещё нет у клиента или материал битый (error-«шахматка») — не рисуем
-- ничего и пробуем снова через 5 секунд, чтобы экран не закрывался магентой.
local function GetFxMaterial(name)
	local now = RealTime()
	local entry = materials[name]
	if (entry and (entry.mat or now < entry.nextTry)) then
		return entry.mat
	end

	local path = "afterlight/disciplines/potence/" .. name .. ".png"
	local mat = file.Exists("materials/" .. path, "GAME") and Material(path) or nil
	if (mat and mat:IsError()) then
		mat = nil
	end

	materials[name] = {mat = mat, nextTry = now + 5}
	return mat
end

-- === Амбиент Могущества ===
-- states: off -> wait (пауза после звука активации) -> in (набор громкости)
-- и out (плавное затухание) -> off с остановкой канала.
local ambient = {channel = nil, loading = false, volume = 0, state = "off", startAt = 0, path = nil, pathTry = 0}
ix.potence.fx.amb = ambient

local function GetLoopPath(now)
	if (ambient.path or now < ambient.pathTry) then
		return ambient.path
	end

	ambient.pathTry = now + 5
	for _, candidate in ipairs({ix.potence.SOUND_LOOP, ix.potence.SOUND_LOOP_LEGACY}) do
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
		ambient.startAt = now + (ix.potence.AMBIENT_DELAY or 1.2)
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
		ambient.volume = math.min(ambient.volume + dt / (ix.potence.AMBIENT_FADE or 1), 1)
	elseif (ambient.state == "out") then
		ambient.volume = math.max(ambient.volume - dt / (ix.potence.AMBIENT_FADE or 1), 0)
	end

	if (ambient.volume <= 0 and ambient.state == "out") then
		channel:Stop()
		ambient.channel = nil
		ambient.state = "off"
		return
	end

	channel:SetVolume(ambient.volume * (ix.potence.AMBIENT_VOLUME or 0.7))
end

hook.Add("HUDPaint", "AfterlightPotenceScreenFx", function()
	local client = LocalPlayer()
	if (!IsValid(client)) then return end
	local fx = ix.potence.fx

	local active = client:GetNW2Int("afterlightPotenceLevel", 0) > 0
		and client:GetNW2Float("afterlightPotenceEnd", 0) > CurTime()

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

	-- Общая мягкая пульсация ауры.
	local pulse = 0.75 + 0.25 * math.sin(now * 3.1)

	for index = 1, #LAYERS do
		local layer = fx.layers[index]
		if (!layer) then
			layer = {env = 0, target = 0, next = 0}
			fx.layers[index] = layer
		end

		-- Каждый слой живёт своей жизнью: вспышка возникает случайно,
		-- её цель плавно распадается, а огибающая гладко тянется к цели —
		-- молнии появляются и прерываются без жёстких переключений.
		layer.target = layer.target * math.exp(-dt * 2.2)
		if (now >= layer.next) then
			layer.next = now + math.Rand(0.3, 1.1)
			layer.target = math.Rand(0.55, 1)
		end
		layer.env = layer.env + (layer.target - layer.env) * math.min(1, dt * 14)

		-- Третий слой — «дыхание» ауры: едва заметная постоянная основа,
		-- даёт эффекту непрерывность и глубину между вспышками.
		local base = index == 3 and 0.3 + 0.2 * math.sin(now * 1.7 + 1) or 0

		local strength = math.Clamp((layer.env + base) * pulse, 0, 1)
		local material = GetFxMaterial(LAYERS[index])
		if (material and strength > 0.02) then
			surface.SetDrawColor(255, 255, 255, math.Clamp(255 * fx.alpha * strength, 0, 255))
			surface.SetMaterial(material)
			surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
		end
	end
end)
