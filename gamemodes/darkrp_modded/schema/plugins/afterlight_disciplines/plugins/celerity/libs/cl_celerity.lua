local PLUGIN = PLUGIN

-- libs включаются в алфавитном порядке: cl_celerity.lua идёт РАНЬШЕ
-- sh_celerity_levels.lua, поэтому таблицу создаём здесь сами.
ix.celerity = ix.celerity or {}

-- Нуарная аура скорости: процедурная тёмная виньетка + два наложенных слоя
-- светлых штрихов (png с запечённой прозрачностью), живущих своими вспышками,
-- редкие ветровые штрихи; шлейф «преломления воздуха» = серверные ленты
-- util.SpriteTrail + крошечные клиентские искры — только во время фактического
-- спринта на 3+. Звук ветра — тоже только при спринте.
ix.celerity.fx = ix.celerity.fx or {alpha = 0, slashes = {}, layers = {}, ripple = {samples = {}, next = 0}}

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

-- === Преломление воздуха в стиле Matrix (только спринт на 3+) ===
-- Референс — «рябь преломлённого воздуха» вокруг тела: ряды волнистых
-- линзовых штрихов. Реализовано ПРОВЕРЕННЫМ 2D-механизмом (surface +
-- сгенерированный png с запечённой прозрачностью — так уже работают слои ауры):
-- во время спринта снимаются мировые «эхо»-точки за персонажем и за спиной
-- тают ряды ряби (0.6с), плюс живая рябь мерцает на самом теле. Ни частиц, ни
-- лент — никакого дыма и никакой магенты.
local RIPPLE_PATH = "afterlight/disciplines/celerity/celerity_ripple.png"
local rippleMaterial = nil
local rippleNextTry = 0

local function GetRippleMaterial(now)
	if (rippleMaterial or now < rippleNextTry) then
		return rippleMaterial
	end

	local mat = file.Exists("materials/" .. RIPPLE_PATH, "GAME") and Material(RIPPLE_PATH) or nil
	if (mat and mat:IsError()) then
		mat = nil
	end
	rippleMaterial = mat
	rippleNextTry = now + 5
	return mat
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
	fx.ripple = fx.ripple or {samples = {}, next = 0}

	local level = client:GetNW2Int("afterlightCelerityLevel", 0)
	local active = level > 0 and client:GetNW2Float("afterlightCelerityEnd", 0) > CurTime()
	-- Спринт читаем СЕРВЕРНЫМ флагом: сервер видит точную ходьбу/спринт
	-- (включая наше ускорение), а клиентские догадки по скорости врали —
	-- ускоренная ходьба после активации проходила порог, и ветер гудел зря.
	local sprinting = client:GetNW2Bool("afterlightCeleritySprint", false)

	local dt = FrameTime()
	local now = RealTime()

	-- Ветер — только когда серверный флаг спринта поднят на 3+ уровне.
	UpdateAmbience(active and level >= 3 and sprinting, now, dt)

	-- Плавные вход и выход ауры: 1 секунда в каждую сторону.
	local target = active and 1 or 0
	if (fx.alpha < target) then
		fx.alpha = math.min(fx.alpha + dt, 1)
	elseif (fx.alpha > target) then
		fx.alpha = math.max(fx.alpha - dt, 0)
	end
	if (fx.alpha <= 0.01) then
		fx.slashes = {}
		fx.ripple.samples = {}
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

	-- 4) Преломление воздуха в стиле Matrix: пока серверный флаг спринта поднят,
	-- за персонажем каждые 0.045с снимаются мировые «эхо»-точки; каждая 0.6с
	-- тает рябью за спиной — шлейф преломления, а не дым.
	local ripple = fx.ripple
	local moving = client:GetVelocity():Length2D() > 80
	if (active and level >= 3 and sprinting and moving and now >= ripple.next) then
		ripple.next = now + 0.045
		local bone = client.LookupBone and client:LookupBone("ValveBiped.Bip01_Spine2") or nil
		local origin = (bone and bone > 0 and client:GetBonePosition(bone))
			or (client:GetPos() + Vector(0, 0, 50))
		ripple.samples[#ripple.samples + 1] = {
			pos = origin + Vector(math.Rand(-6, 6), math.Rand(-6, 6), math.Rand(-10, 10)),
			born = now,
			scale = level >= 4 and 1.5 or 1
		}
		if (#ripple.samples > 26) then
			table.remove(ripple.samples, 1)
		end
	end

	local rmat = GetRippleMaterial(now)
	if (rmat) then
		for i = #ripple.samples, 1, -1 do
			local sample = ripple.samples[i]
			local age = now - sample.born
			if (age > 0.6) then
				table.remove(ripple.samples, i)
			else
				local scr = sample.pos:ToScreen()
				if (scr.visible) then
					local k = 1 - age / 0.6
					local w = 150 * sample.scale * (0.75 + 0.25 * k)
					surface.SetDrawColor(255, 255, 255, math.Clamp(120 * k * fx.alpha, 0, 255))
					surface.SetMaterial(rmat)
					surface.DrawTexturedRect(scr.x - w / 2, scr.y - w / 4, w, w / 2)
				end
			end
		end

		-- Живая рябь на теле: два якоря мерцают в противофазе — воздух
		-- «дрожит» вокруг силуэта, как в референсе.
		if (active and level >= 3 and sprinting and moving) then
			local anchors = {
				client:GetPos() + Vector(0, 0, 62),
				client:GetPos() + Vector(0, 0, 30)
			}
			for i = 1, 2 do
				local flick = math.sin(now * (6.5 + i * 2.1) + i * 2.4)
				if (flick > 0.45) then
					local scr = anchors[i]:ToScreen()
					if (scr.visible) then
						local w = (i == 1 and 120 or 160) * (level >= 4 and 1.4 or 1)
						surface.SetDrawColor(255, 255, 255, math.Clamp(75 * flick * fx.alpha, 0, 255))
						surface.SetMaterial(rmat)
						surface.DrawTexturedRect(scr.x - w / 2, scr.y - w / 4, w, w / 2)
					end
				end
			end
		end
	end
end)
