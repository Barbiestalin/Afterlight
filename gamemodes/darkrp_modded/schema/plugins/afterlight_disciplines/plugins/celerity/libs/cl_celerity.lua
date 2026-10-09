local PLUGIN = PLUGIN

-- libs включаются в алфавитном порядке: cl_celerity.lua идёт РАНЬШЕ
-- sh_celerity_levels.lua, поэтому таблицу создаём здесь сами.
ix.celerity = ix.celerity or {}

-- Нуарная аура скорости: процедурная тёмная виньетка + два наложенных слоя
-- светлых штрихов (png с запечённой прозрачностью), живущих своими вспышками,
-- редкие ветровые штрихи; шлейф — серверные ленты util.SpriteTrail на штатной
-- текстуре «трубы» (trails/tube.vmt) — только во время фактического спринта
-- на 3+. Звук ветра — тоже только при спринте.
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

-- === Трейл: короткая лента вдоль позвоночника, целиком на клиенте ===
-- Каждые 0.045с снимается позиция кости позвоночника через GetBonePosition —
-- тот же скелет, которым рисуется модель: точка НЕ отстаёт, НЕ улетает вперёд
-- и не «мотается», как env_spritetrail с аттачментами (на кастомных моделях
-- аттачменты уезжают при смене анимаций — от этого был вынос трейла вперёд и
-- мотание после 13с). Между снимками рисуются балки с проверенной текстурой
-- trails/tube; лента живёт 0.18с и существует только при серверном флаге
-- спринта: отжали shift — дотухает мгновенно.
local TRAIL_LIFE = 0.18
local trailMat = nil
local trailMatNextTry = 0

local function GetTrailMaterial(now)
	if (trailMat or now < trailMatNextTry) then
		return trailMat
	end
	local mat = Material("trails/tube")
	if (mat and mat:IsError()) then
		mat = nil
	end
	trailMat = mat
	trailMatNextTry = now + 5
	return mat
end

hook.Add("PostDrawTranslucentRenderables", "AfterlightCelerityTrail", function()
	local now = RealTime()
	local fx = ix.celerity.fx
	fx.trailRibbons = fx.trailRibbons or {}
	local mat = GetTrailMaterial(now)

	-- Лента за КАЖДЫМ игроком с флагом: другие видят ваш шлейф, вы — чужой.
	for _, ply in ipairs(player.GetAll()) do
		local ribbon = fx.trailRibbons[ply]
		if (!ribbon) then
			ribbon = {}
			fx.trailRibbons[ply] = ribbon
		end

		local level = IsValid(ply) and ply:GetNW2Int("afterlightCelerityLevel", 0) or 0
		local active = level > 0 and ply:GetNW2Float("afterlightCelerityEnd", 0) > CurTime()
		local sprinting = ply:GetNW2Bool("afterlightCeleritySprint", false)
		local moving = IsValid(ply) and ply:GetVelocity():Length2D() > 80

		if (mat and active and level >= 3 and sprinting and moving) then
			local bone = ply.LookupBone and ply:LookupBone("ValveBiped.Bip01_Spine2") or nil
			if (bone and bone > 0 and now >= (ribbon.next or 0)) then
				ribbon.next = now + 0.045
				local pos = ply:GetBonePosition(bone)
				if (pos) then
					ribbon[#ribbon + 1] = {pos = pos, t = now}
				end
			end
		end

		while (#ribbon > 0 and now - ribbon[1].t > TRAIL_LIFE) do
			table.remove(ribbon, 1)
		end
		if (#ribbon > 32) then
			table.remove(ribbon, 1)
		end

		if (mat and #ribbon >= 2) then
			local scale = level >= 4 and 1.45 or 1
			render.SetMaterial(mat)
			for i = 2, #ribbon do
				local a = ribbon[i - 1]
				local b = ribbon[i]
				local k = 1 - (now - b.t) / TRAIL_LIFE
				if (k > 0) then
					-- Ширина соразмерна туловищу: широкая бледная полоса + яркое ядро.
					render.DrawBeam(a.pos, b.pos, (6 + 18 * k) * scale, 0, i * 0.15,
						Color(140, 180, 220, math.Clamp(50 * k, 0, 255)))
					render.DrawBeam(a.pos, b.pos, (3 + 11 * k) * scale, 0, i * 0.15,
						Color(190, 220, 245, math.Clamp(95 * k, 0, 255)))
				end
			end
		end
	end
end)

-- === Размытие аномального движения: полупрозрачные послеобразы ===
-- Пока поднят серверный флаг спринта, каждые 0.09с снимается слепок персонажа:
-- clientside-копия модели с полупрозрачным матовым стеклом остаётся в точке
-- съёма и тает за 0.3с. Несколько тающих копий подряд = силуэт буквально
-- «размывается» из общего вида, как при аномальной скорости. Если материала
-- нет на клиенте — послеобразы молча отключаются, трейл продолжает работать.
local GHOST_MATERIAL = "models/props_c17/frostedglass_01a"
local ghostOk = nil
local ghostNextTry = 0

local function GhostsAvailable(now)
	if (ghostOk ~= nil or now < ghostNextTry) then
		return ghostOk == true
	end
	ghostOk = file.Exists("materials/" .. GHOST_MATERIAL .. ".vmt", "GAME") == true
		and !Material(GHOST_MATERIAL):IsError()
	ghostNextTry = now + 5
	return ghostOk
end

local function UpdateGhostsFor(ply, fx, active, level, sprinting, now)
	fx.ghosts = fx.ghosts or {}
	if (!IsValid(ply)) then
		local dead = fx.ghosts[ply]
		if (dead) then
			for _, entry in ipairs(dead.list) do
				if (IsValid(entry.cm)) then
					entry.cm:Remove()
				end
			end
			fx.ghosts[ply] = nil
		end
		return
	end

	local ghosts = fx.ghosts[ply]
	if (!ghosts) then
		ghosts = {list = {}, next = 0}
		fx.ghosts[ply] = ghosts
	end
	local moving = ply:GetVelocity():Length2D() > 150

	if (active and level >= 3 and sprinting and moving and GhostsAvailable(now)) then
		if (now >= ghosts.next) then
			ghosts.next = now + 0.09
			local cm = ClientsideModel(ply:GetModel())
			if (IsValid(cm)) then
				cm:SetSkin(ply:GetSkin())
				cm:SetMaterial(GHOST_MATERIAL)
				cm:SetSequence(ply:GetSequence())
				cm:SetCycle(ply:GetCycle())
				-- Замораживаем анимацию слепка: иначе копия доигрывает бег и
				-- «наклоняется/переворачивается» — слепок держит позу съёма.
				cm:SetPlaybackRate(0)
				cm:SetPos(ply:GetPos())
				-- Только yaw: углы игрока несут pitch взгляда, и с ним копии
				-- «ложились на землю» и переворачивались. Слепок стоит ровно.
				cm:SetAngles(Angle(0, ply:GetAngles().y, 0))
				ghosts.list[#ghosts.list + 1] = {cm = cm, born = now}
				if (#ghosts.list > 6) then
					local old = table.remove(ghosts.list, 1)
					if (IsValid(old.cm)) then
						old.cm:Remove()
					end
				end
			end
		end
	end

	for i = #ghosts.list, 1, -1 do
		local entry = ghosts.list[i]
		local age = now - entry.born
		if (age > 0.55 or !IsValid(entry.cm)) then
			if (IsValid(entry.cm)) then
				entry.cm:Remove()
			end
			table.remove(ghosts.list, i)
		else
			-- Entity:SetColor в GMod принимает Color-таблицу (расширение
			-- entity.lua), четыре числа ломают хук. Плавное поочерёдное
			-- затухание каждой копии за 0.55с.
			local k = 1 - age / 0.55
			entry.cm:SetColor(Color(185, 215, 240, math.Clamp(90 * k, 0, 255)))
		end
	end
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
	-- Спринт читаем СЕРВЕРНЫМ флагом: сервер видит точную ходьбу/спринт
	-- (включая наше ускорение), а клиентские догадки по скорости врали —
	-- ускоренная ходьба после активации проходила порог, и ветер гудел зря.
	local sprinting = client:GetNW2Bool("afterlightCeleritySprint", false)

	local dt = FrameTime()
	local now = RealTime()

	-- Ветер — только когда серверный флаг спринта поднят на 3+ уровне.
	UpdateAmbience(active and level >= 3 and sprinting, now, dt)
	-- Послеобразы-размытие — по всем игрокам с серверным флагом спринта:
	-- ваш смаз видят и другие игроки.
	for _, ply in ipairs(player.GetAll()) do
		local lvl = ply:GetNW2Int("afterlightCelerityLevel", 0)
		local act = lvl > 0 and ply:GetNW2Float("afterlightCelerityEnd", 0) > CurTime()
		local spr = ply:GetNW2Bool("afterlightCeleritySprint", false)
		UpdateGhostsFor(ply, fx, act, lvl, spr, now)
	end

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
