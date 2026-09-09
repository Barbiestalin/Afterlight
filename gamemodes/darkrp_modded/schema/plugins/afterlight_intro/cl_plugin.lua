if (!CLIENT) then return end

--[[
	Afterlight Intro
	Клиентская заставка. Музыкой заведует общий контроллер AfterlightMusic
	(плагин afterlight_menu_music): интро не создаёт собственный канал и не
	трогает громкость, а только сообщает контроллеру, что ему нужен звук.
--]]

local INTRO = {}

-- Единственная точка связи заставки с музыкой. Контроллер может быть ещё не
-- загружен или вовсе отключён, поэтому обращение защищено.
local function SetMusicContext(bActive)
	if (AfterlightMusic and AfterlightMusic.SetContext) then
		AfterlightMusic:SetContext(AfterlightMusic.CONTEXT_INTRO or "intro", bActive)
	end
end

INTRO.title = "AFTERLIGHT"
INTRO.subtitle = "Хроники ночи начинаются здесь"
INTRO.description = "Добро пожаловать в мир крови, тайн и древних клятв."
INTRO.buttonText = "ВОЙТИ В НОЧЬ"

INTRO.backgroundPath = "afterlight/intro/intro.jpg"
INTRO.decorPaths = {
	frame = "afterlight/intro/generated/gothic_frame.png",
	rose = "afterlight/intro/generated/rose_window.png",
	blood = "afterlight/intro/generated/blood_bloom.png",
	film = "afterlight/intro/generated/film_damage.png"
}
-- Полноценная постановка раскрывается примерно за двадцать секунд.
INTRO.buttonDelay = 19
INTRO.fadeOutDuration = 1.1
INTRO.materialAttempts = 12
INTRO.materialRetryDelay = 0.6

INTRO.colors = {
	black = Color(4, 2, 3),
	ivory = Color(224, 216, 205),
	muted = Color(174, 163, 158),
	blood = Color(116, 8, 24),
	bloodBright = Color(186, 25, 48)
}

INTRO.timerAutoStart = "AfterlightIntroAutoStart"
INTRO.timerButton = "AfterlightIntroButtonAppear"
INTRO.timerMaterial = "AfterlightIntroMaterialRetry"
INTRO.hookMenu = "AfterlightHideHelixCharacterMenu"
INTRO.hookResolution = "AfterlightIntroResolutionChanged"

INTRO.shown = false
INTRO.active = false
INTRO.closing = false
INTRO.loadGeneration = 0
INTRO.frame = nil
INTRO.curtain = nil
INTRO.background = nil
INTRO.decor = {}

local function Clamp01(value)
	return math.Clamp(value, 0, 1)
end

local function SmoothStep(value)
	value = Clamp01(value)
	return value * value * (3 - 2 * value)
end

local function Phase(elapsed, delay, duration)
	return SmoothStep((elapsed - delay) / duration)
end

local function Alpha(color, alpha)
	return Color(color.r, color.g, color.b, math.Clamp(alpha, 0, 255))
end

local function EaseInCubic(value)
	value = Clamp01(value)
	return value * value * value
end

local function EaseOutCubic(value)
	value = 1 - Clamp01(value)
	return 1 - value * value * value
end

local function EaseInOutSine(value)
	value = Clamp01(value)
	return -(math.cos(math.pi * value) - 1) * 0.5
end

function INTRO:CreateFonts()
	local height = ScrH()

	-- Georgia и Times New Roman есть у стандартного Windows-клиента и корректно
	-- отображают кириллицу. Атмосферу создаёт композиция, а не нечитаемый blackletter.
	surface.CreateFont("AfterlightIntroTitle", {
		font = "Georgia",
		size = math.Clamp(math.floor(height * 0.088), 56, 104),
		weight = 700,
		antialias = true,
		extended = true
	})

	surface.CreateFont("AfterlightIntroSubtitle", {
		font = "Georgia",
		size = math.Clamp(math.floor(height * 0.026), 20, 31),
		weight = 500,
		antialias = true,
		extended = true
	})

	surface.CreateFont("AfterlightIntroText", {
		font = "Times New Roman",
		size = math.Clamp(math.floor(height * 0.021), 17, 24),
		weight = 400,
		antialias = true,
		extended = true
	})

	surface.CreateFont("AfterlightIntroButton", {
		font = "Georgia",
		size = math.Clamp(math.floor(height * 0.021), 18, 24),
		weight = 600,
		antialias = true,
		extended = true
	})

	surface.CreateFont("AfterlightIntroSmall", {
		font = "Times New Roman",
		size = math.Clamp(math.floor(height * 0.014), 13, 17),
		weight = 400,
		antialias = true,
		extended = true
	})
end

function INTRO:SetCharacterMenuVisible(state)
	if (ix and ix.gui and IsValid(ix.gui.characterMenu)) then
		ix.gui.characterMenu:SetVisible(state)
		ix.gui.characterMenu:SetAlpha(state and 255 or 0)
	end
end

function INTRO:CreateCurtain()
	if (IsValid(self.curtain)) then return end

	local panel = vgui.Create("DPanel")
	panel:SetSize(ScrW(), ScrH())
	panel:SetPos(0, 0)
	panel:SetZPos(999999)
	panel:SetMouseInputEnabled(false)
	panel:SetKeyboardInputEnabled(false)
	panel.Paint = function(_, w, h)
		surface.SetDrawColor(4, 2, 3, 255)
		surface.DrawRect(0, 0, w, h)
	end

	self.curtain = panel
end

-- Рисует изображение в режиме cover без искажения пропорций.
function INTRO:DrawCoverMaterial(material, w, h, zoom, driftX, driftY)
	local materialW = math.max(material:Width(), 1)
	local materialH = math.max(material:Height(), 1)
	local materialAspect = materialW / materialH
	local screenAspect = w / math.max(h, 1)
	local u0, v0, u1, v1 = 0, 0, 1, 1

	if (materialAspect > screenAspect) then
		local visible = screenAspect / materialAspect
		u0 = (1 - visible) * 0.5
		u1 = 1 - u0
	else
		local visible = materialAspect / screenAspect
		v0 = (1 - visible) * 0.5
		v1 = 1 - v0
	end

	zoom = math.max(zoom or 1, 1)
	local centerU = (u0 + u1) * 0.5 + (driftX or 0)
	local centerV = (v0 + v1) * 0.5 + (driftY or 0)
	local halfU = (u1 - u0) * 0.5 / zoom
	local halfV = (v1 - v0) * 0.5 / zoom

	surface.SetMaterial(material)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawTexturedRectUV(0, 0, w, h, centerU - halfU, centerV - halfV, centerU + halfU, centerV + halfV)
end

function INTRO:LoadDecorMaterials()
	for key, path in pairs(self.decorPaths) do
		local material = Material(path, "smooth noclamp")
		self.decor[key] = material:IsError() and nil or material
	end
end

function INTRO:DrawDecor(key, x, y, w, h, color, rotation)
	local material = self.decor[key]
	if (!material or material:IsError()) then return false end

	surface.SetMaterial(material)
	surface.SetDrawColor(color)

	if (rotation) then
		surface.DrawTexturedRectRotated(x, y, w, h, rotation)
	else
		surface.DrawTexturedRect(x, y, w, h)
	end

	return true
end

function INTRO:DrawVignette(w, h)
	-- Многослойная виньетка без дополнительной текстуры.
	local steps = 14

	for i = 1, steps do
		local fraction = i / steps
		local sideW = w * 0.018
		local topH = h * 0.014
		local alpha = math.floor(7 + fraction * 6)

		surface.SetDrawColor(0, 0, 0, alpha)
		surface.DrawRect((i - 1) * sideW, 0, sideW + 1, h)
		surface.DrawRect(w - i * sideW, 0, sideW + 1, h)
		surface.DrawRect(0, (i - 1) * topH, w, topH + 1)
		surface.DrawRect(0, h - i * topH, w, topH + 1)
	end

	surface.SetDrawColor(0, 0, 0, 145)
	surface.DrawRect(0, 0, w, h * 0.12)
	surface.DrawRect(0, h * 0.88, w, h * 0.12)
end

function INTRO:DrawOrnament(x, y, width, alpha, reveal)
	reveal = SmoothStep(reveal)
	local half = width * 0.5 * reveal
	local blood = self.colors.blood

	surface.SetDrawColor(blood.r, blood.g, blood.b, alpha)
	surface.DrawRect(x - half, y, half - 12, 1)
	surface.DrawRect(x + 12, y, half - 12, 1)

	draw.NoTexture()
	surface.DrawPoly({
		{x = x, y = y - 5},
		{x = x + 6, y = y},
		{x = x, y = y + 5},
		{x = x - 6, y = y}
	})
end

function INTRO:BuildAtmosphere(frame)
	-- Все частицы создаются один раз. В Paint нет случайной генерации и мусора для GC.
	frame.motes = {}
	frame.rain = {}
	frame.drips = {}
	frame.spatter = {}
	frame.ravens = {}
	frame.shards = {}

	for i = 1, 28 do
		frame.motes[i] = {
			x = math.Rand(0.06, 0.94),
			y = math.Rand(0.04, 0.96),
			speed = math.Rand(0.003, 0.012),
			sway = math.Rand(0.002, 0.009),
			phase = math.Rand(0, math.pi * 2),
			size = math.Rand(0.7, 1.8),
			alpha = math.random(5, 17)
		}
	end

	for i = 1, 42 do
		frame.rain[i] = {
			x = math.Rand(-0.05, 1.05),
			y = math.Rand(0, 1),
			speed = math.Rand(0.10, 0.22),
			length = math.Rand(0.010, 0.026),
			alpha = math.random(3, 11),
			delay = math.Rand(0, 2)
		}
	end

	for i = 1, 7 do
		frame.drips[i] = {
			offset = (i - 4) / 3,
			length = math.Rand(9, 28),
			delay = math.Rand(0.1, 1.2),
			phase = math.Rand(0, math.pi * 2)
		}
	end

	for i = 1, 18 do
		frame.spatter[i] = {
			angle = math.Rand(0, math.pi * 2),
			distance = math.Rand(28, 118),
			size = math.Rand(1, 3.2),
			delay = math.Rand(0, 0.45)
		}
	end

	-- Дальний клин воронов проходит до появления названия и не пересекает UI.
	for i = 1, 7 do
		frame.ravens[i] = {
			delay = 2.4 + i * 0.34 + math.Rand(0, 0.28),
			duration = math.Rand(5.8, 7.4),
			y = math.Rand(0.13, 0.29),
			scale = math.Rand(0.72, 1.24),
			phase = math.Rand(0, math.pi * 2),
			offset = (i - 4) * 0.018
		}
	end

	-- Осколки «витража» рождаются из удара капли вместе с кровавыми нитями.
	for i = 1, 14 do
		frame.shards[i] = {
			angle = (i / 14) * math.pi * 2 + math.Rand(-0.13, 0.13),
			distance = math.Rand(72, 185),
			length = math.Rand(7, 19),
			width = math.Rand(2.2, 5.5),
			delay = math.Rand(0, 1.0),
			turn = math.Rand(-1, 1)
		}
	end
end

function INTRO:DrawMotes(frame, w, h, elapsed)
	for _, mote in ipairs(frame.motes or {}) do
		local y = (mote.y - elapsed * mote.speed) % 1
		local x = mote.x + math.sin(elapsed * 0.35 + mote.phase) * mote.sway
		local pulse = 0.55 + math.sin(elapsed * 0.8 + mote.phase) * 0.35

		surface.SetDrawColor(205, 180, 160, mote.alpha * pulse)
		surface.DrawRect(x * w, y * h, mote.size, mote.size)
	end
end

function INTRO:DrawRain(frame, w, h, elapsed, alpha)
	for _, drop in ipairs(frame.rain or {}) do
		local progress = (drop.y + math.max(elapsed - drop.delay, 0) * drop.speed) % 1.08
		local x = drop.x * w
		local y = progress * h
		local length = drop.length * h

		surface.SetDrawColor(185, 196, 205, drop.alpha * alpha)
		surface.DrawLine(x, y, x - length * 0.18, y + length)
	end
end

function INTRO:DrawRavens(frame, w, h, elapsed, reveal)
	if (reveal <= 0) then return end

	for _, raven in ipairs(frame.ravens or {}) do
		local raw = (elapsed - raven.delay) / raven.duration
		if (raw > 0 and raw < 1) then
			local progress = EaseInOutSine(raw)
			local fade = Phase(raw, 0, 0.12) * (1 - Phase(raw, 0.82, 0.18))
			local x = Lerp(progress, -w * 0.08, w * 1.08)
			local y = h * (raven.y + raven.offset) + math.sin(progress * math.pi * 2 + raven.phase) * h * 0.012
			local size = math.Clamp(h * 0.011 * raven.scale, 6, 15)
			local flap = math.sin(elapsed * 5.2 + raven.phase) * size * 0.42
			local alpha = 82 * fade * reveal

			draw.NoTexture()
			surface.SetDrawColor(3, 2, 4, alpha)
			surface.DrawPoly({
				{x = x, y = y},
				{x = x - size * 1.35, y = y - size * 0.24 - flap},
				{x = x - size * 0.52, y = y + size * 0.27}
			})
			surface.DrawPoly({
				{x = x, y = y},
				{x = x + size * 1.35, y = y - size * 0.24 - flap},
				{x = x + size * 0.52, y = y + size * 0.27}
			})
			surface.DrawPoly({
				{x = x, y = y - size * 0.24},
				{x = x + size * 0.28, y = y + size * 0.55},
				{x = x, y = y + size * 0.40},
				{x = x - size * 0.28, y = y + size * 0.55}
			})

			-- Едва заметная холодная кромка отделяет силуэт от тёмного неба.
			surface.SetDrawColor(120, 112, 119, alpha * 0.22)
			surface.DrawLine(x - size * 1.28, y - size * 0.24 - flap, x, y)
			surface.DrawLine(x, y, x + size * 1.28, y - size * 0.24 - flap)
		end
	end
end

function INTRO:DrawGlassShards(frame, x, y, elapsed)
	local impactTime = 5.90

	for _, shard in ipairs(frame.shards or {}) do
		local progress = Phase(elapsed, impactTime + shard.delay, 2.35)
		local fade = 1 - Phase(elapsed, 9.5 + shard.delay, 2.3)

		if (progress > 0 and fade > 0) then
			local distance = shard.distance * EaseOutCubic(progress)
			local angle = shard.angle + shard.turn * progress * 0.28
			local cx = x + math.cos(angle) * distance
			local cy = y + math.sin(angle) * distance * 0.63
			local tx, ty = math.cos(angle), math.sin(angle)
			local nx, ny = -ty, tx
			local halfLength = shard.length * 0.5
			local halfWidth = shard.width * 0.5

			draw.NoTexture()
			surface.SetDrawColor(130, 17, 35, 38 * fade)
			surface.DrawPoly({
				{x = cx + tx * halfLength, y = cy + ty * halfLength},
				{x = cx - tx * halfLength + nx * halfWidth, y = cy - ty * halfLength + ny * halfWidth},
				{x = cx - tx * halfLength - nx * halfWidth, y = cy - ty * halfLength - ny * halfWidth}
			})
			surface.SetDrawColor(203, 187, 180, 18 * fade)
			surface.DrawLine(cx + tx * halfLength, cy + ty * halfLength, cx - tx * halfLength + nx * halfWidth, cy - ty * halfLength + ny * halfWidth)
		end
	end
end

function INTRO:DrawCircleOutline(x, y, radius, segments, color, progress, rotation)
	progress = Clamp01(progress or 1)
	rotation = rotation or 0
	local count = math.max(1, math.floor(segments * progress))
	local previousX, previousY

	surface.SetDrawColor(color)

	for i = 0, count do
		local angle = rotation + (i / segments) * math.pi * 2
		local pointX = x + math.cos(angle) * radius
		local pointY = y + math.sin(angle) * radius

		if (previousX) then
			surface.DrawLine(previousX, previousY, pointX, pointY)
		end

		previousX, previousY = pointX, pointY
	end
end

function INTRO:DrawMasqueradeSeal(x, y, radius, elapsed, reveal, alpha)
	if (reveal <= 0 or alpha <= 0) then return end

	local rotation = elapsed * 0.035
	local blood = Color(130, 11, 30, alpha)
	local ghost = Color(208, 195, 187, alpha * 0.34)
	local innerRadius = radius * 0.72

	self:DrawCircleOutline(x, y, radius, 72, blood, reveal, rotation)
	self:DrawCircleOutline(x, y, radius - 4, 72, ghost, reveal, -rotation * 0.7)
	self:DrawCircleOutline(x, y, innerRadius, 56, blood, reveal, -rotation * 0.45)

	-- Радиальные засечки напоминают часовую шкалу и древнюю печать.
	local marks = math.floor(12 * reveal)
	for i = 1, marks do
		local angle = rotation + (i / 12) * math.pi * 2
		local length = (i % 3 == 0) and 11 or 6
		local x1 = x + math.cos(angle) * (radius - length)
		local y1 = y + math.sin(angle) * (radius - length)
		local x2 = x + math.cos(angle) * radius
		local y2 = y + math.sin(angle) * radius
		surface.SetDrawColor(blood)
		surface.DrawLine(x1, y1, x2, y2)
	end

end

function INTRO:DrawCrimsonSigil(x, y, h, elapsed, heartbeat)
	-- Фигура рождается только после того, как кровавые нити почти завершили
	-- «паутину». Все её слои исключительно красные — светлого ромба здесь нет.
	local reveal = Phase(elapsed, 8.75, 2.65)
	if (reveal <= 0) then return end

	local bodyReveal = Phase(elapsed, 8.75, 1.65)
	local coreReveal = Phase(elapsed, 9.65, 1.25)
	local size = math.Clamp(h * 0.105, 72, 116) * (1 + heartbeat * 0.012)
	local top = y - size * 0.76
	local bottom = y + size * 0.86

	draw.NoTexture()

	-- Глубокая тень отделяет знак от кровавой паутины.
	surface.SetDrawColor(18, 0, 6, 118 * bodyReveal)
	surface.DrawPoly({
		{x = x + 3, y = top + 4},
		{x = x + size * 0.25 + 3, y = y - size * 0.12 + 4},
		{x = x + size * 0.11 + 3, y = y + size * 0.20 + 4},
		{x = x + 3, y = bottom + 4},
		{x = x - size * 0.11 + 3, y = y + size * 0.20 + 4},
		{x = x - size * 0.25 + 3, y = y - size * 0.12 + 4}
	})

	-- Основной вытянутый клык — преобразованный остаток упавшей капли.
	surface.SetDrawColor(101, 2, 21, 225 * bodyReveal)
	surface.DrawPoly({
		{x = x, y = top},
		{x = x + size * 0.25, y = y - size * 0.12},
		{x = x + size * 0.11, y = y + size * 0.20},
		{x = x, y = bottom},
		{x = x - size * 0.11, y = y + size * 0.20},
		{x = x - size * 0.25, y = y - size * 0.12}
	})

	-- Внутренние грани дают фигуре объём без белого блика.
	surface.SetDrawColor(181, 17, 40, 150 * bodyReveal)
	surface.DrawLine(x, top, x, bottom)
	surface.DrawLine(x, top, x + size * 0.25, y - size * 0.12)
	surface.DrawLine(x, top, x - size * 0.25, y - size * 0.12)
	surface.SetDrawColor(61, 0, 14, 180 * bodyReveal)
	surface.DrawLine(x, y + size * 0.08, x + size * 0.11, y + size * 0.20)
	surface.DrawLine(x, y + size * 0.08, x - size * 0.11, y + size * 0.20)

	-- Живое кровавое ядро реагирует на спокойный ритм лишь изменением размера.
	local coreSize = size * (0.105 + heartbeat * 0.012) * coreReveal
	surface.SetDrawColor(204, 20, 43, 215 * coreReveal)
	surface.DrawPoly({
		{x = x, y = y - coreSize * 1.45},
		{x = x + coreSize * 0.70, y = y - coreSize * 0.18},
		{x = x + coreSize * 0.82, y = y + coreSize * 0.42},
		{x = x, y = y + coreSize * 1.55},
		{x = x - coreSize * 0.82, y = y + coreSize * 0.42},
		{x = x - coreSize * 0.70, y = y - coreSize * 0.18}
	})
end

function INTRO:DrawBloodDrips(frame, centerX, y, width, elapsed, reveal)
	if (reveal <= 0) then return end

	for _, drip in ipairs(frame.drips or {}) do
		local localProgress = Phase(elapsed, 0.65 + drip.delay, 1.5)
		local x = centerX + drip.offset * width * 0.43
		local length = drip.length * localProgress
		local pulse = 0.75 + math.sin(elapsed * 0.7 + drip.phase) * 0.18

		surface.SetDrawColor(99, 3, 20, 105 * reveal * pulse)
		surface.DrawRect(x, y, 1, length)

		if (localProgress >= 0.98) then
			draw.NoTexture()
			surface.DrawPoly({
				{x = x - 2, y = y + length},
				{x = x + 3, y = y + length},
				{x = x, y = y + length + 5}
			})
		end
	end
end

function INTRO:DrawSpacedTitle(text, font, x, y, spacing, reveal, color)
	surface.SetFont(font)
	local characters = {}
	local totalWidth = 0

	for i = 1, #text do
		local character = string.sub(text, i, i)
		local width = surface.GetTextSize(character)
		characters[#characters + 1] = {character, width}
		totalWidth = totalWidth + width
	end

	totalWidth = totalWidth + spacing * math.max(#characters - 1, 0)
	local cursor = x - totalWidth * 0.5

	for index, data in ipairs(characters) do
		local letterReveal = Phase(reveal, (index - 1) * 0.055, 0.38)
		local character = data[1]
		local width = data[2]
		local rise = (1 - letterReveal) * 17
		local letterAlpha = color.a * letterReveal

		-- Короткий кровавый след исчезает по мере материализации буквы.
		draw.SimpleText(character, font, cursor + width * 0.5 + 2, y + rise + 3, Color(65, 0, 11, letterAlpha * 0.85), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(character, font, cursor + width * 0.5, y + rise, Color(color.r, color.g, color.b, letterAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		cursor = cursor + width + spacing
	end
end

function INTRO:DrawOpeningShutter(w, h, elapsed)
	local opening = Phase(elapsed, 0.25, 5.35)
	local sideWidth = w * 0.5 * (1 - opening)

	if (sideWidth > 0.5) then
		surface.SetDrawColor(2, 1, 2, 252)
		surface.DrawRect(0, 0, sideWidth + 1, h)
		surface.DrawRect(w - sideWidth, 0, sideWidth + 1, h)

		surface.SetDrawColor(120, 4, 22, 160 * (1 - opening))
		surface.DrawRect(sideWidth, 0, 1, h)
		surface.DrawRect(w - sideWidth - 1, 0, 1, h)
	end
end

function INTRO:GetHeartbeat(elapsed)
	if (elapsed < 5.90) then return 0 end

	-- Спокойный брадикардический ритм: 46 ударов в минуту. Вместо двух
	-- резких вспышек используются сглаженная систолическая волна и более
	-- слабая дикротическая волна. Ритм влияет только на эмблему, не на экран.
	local period = 60 / 46
	local phase = (elapsed - 5.90) % period

	local systoleDistance = (phase - 0.12) / 0.065
	local dicroticDistance = (phase - 0.34) / 0.085
	local systole = math.exp(-(systoleDistance * systoleDistance))
	local dicrotic = math.exp(-(dicroticDistance * dicroticDistance)) * 0.28
	local introduction = Phase(elapsed, 5.90, 1.8)

	return math.Clamp((systole + dicrotic) * 0.62 * introduction, 0, 0.68)
end

function INTRO:DrawBezier(p0, p1, p2, p3, progress, color, segments)
	progress = Clamp01(progress)
	segments = segments or 28
	local count = math.max(1, math.floor(segments * progress))
	local previousX, previousY = p0.x, p0.y

	surface.SetDrawColor(color)

	for i = 1, count do
		local t = (i / segments)
		local inverse = 1 - t
		local x = inverse ^ 3 * p0.x + 3 * inverse ^ 2 * t * p1.x + 3 * inverse * t ^ 2 * p2.x + t ^ 3 * p3.x
		local y = inverse ^ 3 * p0.y + 3 * inverse ^ 2 * t * p1.y + 3 * inverse * t ^ 2 * p2.y + t ^ 3 * p3.y
		surface.DrawLine(previousX, previousY, x, y)
		previousX, previousY = x, y
	end
end

function INTRO:DrawBloodGenesis(frame, x, impactY, w, h, elapsed)
	local gather = Phase(elapsed, 0.75, 2.25)
	local fallRaw = Clamp01((elapsed - 2.85) / 3.05)
	local fall = EaseInCubic(fallRaw)
	local impactTime = 5.90
	local bloom = Phase(elapsed, impactTime, 3.65)
	local sealBirth = Phase(elapsed, 7.15, 3.85)

	-- До падения несколько микрокапель стягиваются в одну тяжёлую каплю.
	if (elapsed < impactTime) then
		for i = 1, 5 do
			local orbit = elapsed * (0.34 + i * 0.025) + i * 1.37
			local orbitRadius = (19 + i * 4) * (1 - gather * 0.72)
			local beadX = x + math.cos(orbit) * orbitRadius
			local beadY = h * 0.075 + math.sin(orbit * 0.73) * orbitRadius * 0.55 + gather * 18
			local size = 1.2 + i * 0.38
			surface.SetDrawColor(103, 4, 21, 120 * gather)
			surface.DrawRect(beadX - size * 0.5, beadY - size * 0.5, size, size)
		end

		local startY = h * 0.075 + 18
		local dropY = Lerp(fall, startY, impactY)
		local velocityStretch = math.sin(fallRaw * math.pi) * 18
		local dropWidth = 8 + gather * 3 - fall * 1.5
		local dropHeight = 15 + velocityStretch
		local tail = 10 + velocityStretch * 0.72

		-- Тонкий след соединяет каплю с верхней тьмой и рвётся перед ударом.
		local trailAlpha = 135 * gather * (1 - Phase(elapsed, 5.15, 0.65))
		surface.SetDrawColor(76, 1, 14, trailAlpha)
		surface.DrawRect(x, math.max(h * 0.075, dropY - tail - 54), 1, tail + 54)

		draw.NoTexture()
		surface.SetDrawColor(112, 3, 22, 238 * gather)
		surface.DrawPoly({
			{x = x, y = dropY - dropHeight * 0.70},
			{x = x + dropWidth * 0.58, y = dropY - dropHeight * 0.08},
			{x = x + dropWidth * 0.40, y = dropY + dropHeight * 0.38},
			{x = x, y = dropY + dropHeight * 0.58},
			{x = x - dropWidth * 0.40, y = dropY + dropHeight * 0.38},
			{x = x - dropWidth * 0.58, y = dropY - dropHeight * 0.08}
		})

		-- Внутренний блик делает каплю объёмной без отдельной текстуры.
		surface.SetDrawColor(214, 61, 72, 105 * gather)
		surface.DrawLine(x - dropWidth * 0.20, dropY - dropHeight * 0.28, x - dropWidth * 0.28, dropY + dropHeight * 0.08)
	end

	if (elapsed < impactTime) then return bloom, sealBirth end

	local impact = Phase(elapsed, impactTime, 0.62)
	local impactFade = 1 - Phase(elapsed, impactTime + 0.35, 1.8)
	local ringRadius = Lerp(EaseOutCubic(impact), 4, math.min(w, h) * 0.105)

	-- Детальная жидкая корона из отдельной прозрачной текстуры. Если файла нет,
	-- процедурные кольца и нити ниже остаются полноценным безопасным fallback.
	local textureBloom = Phase(elapsed, impactTime + 0.12, 2.8)
	local textureSize = math.min(h * 0.47, 510) * EaseOutCubic(textureBloom)
	self:DrawDecor("blood", x, impactY, textureSize, textureSize, Color(154, 24, 40, 74 * textureBloom), elapsed * 1.2)

	self:DrawCircleOutline(x, impactY, ringRadius, 54, Color(132, 8, 29, 115 * impactFade), impact, 0)
	self:DrawCircleOutline(x, impactY, ringRadius * 0.62, 42, Color(204, 35, 52, 70 * impactFade), impact, math.pi)

	for _, speck in ipairs(frame.spatter or {}) do
		local speckReveal = Phase(elapsed, impactTime + speck.delay, 0.28)
		local distance = speck.distance * EaseOutCubic(speckReveal)
		local speckX = x + math.cos(speck.angle) * distance
		local speckY = impactY + math.sin(speck.angle) * distance * 0.58
		local alpha = 125 * speckReveal * (1 - Phase(elapsed, 8.6, 2.2))
		surface.SetDrawColor(104, 2, 20, alpha)
		surface.DrawRect(speckX, speckY, speck.size, speck.size)
	end

	-- Из места удара растут двенадцать кровавых нитей, формируя будущую печать.
	for i = 1, 12 do
		local branchReveal = Phase(elapsed, impactTime + 0.35 + i * 0.10, 2.15)
		local angle = -math.pi * 0.5 + (i / 12) * math.pi * 2
		local radius = math.min(h * 0.18, 178)
		local tangentX = -math.sin(angle)
		local tangentY = math.cos(angle)
		local p0 = {x = x, y = impactY}
		local p1 = {x = x + math.cos(angle) * radius * 0.22 + tangentX * radius * 0.28, y = impactY + math.sin(angle) * radius * 0.12 + tangentY * radius * 0.20}
		local p2 = {x = x + math.cos(angle) * radius * 0.70 - tangentX * radius * 0.14, y = impactY + math.sin(angle) * radius * 0.58 - tangentY * radius * 0.12}
		local p3 = {x = x + math.cos(angle) * radius, y = impactY + math.sin(angle) * radius}
		self:DrawBezier(p0, p1, p2, p3, branchReveal, Color(103, 4, 22, 74 * branchReveal), 30)
	end

	return bloom, sealBirth
end

function INTRO:DrawThornHalo(x, y, radius, elapsed, reveal, alpha)
	if (reveal <= 0 or alpha <= 0) then return end

	local branches = 24
	local visible = math.floor(branches * reveal)
	local rotation = -elapsed * 0.018

	for i = 1, visible do
		local angle = rotation + (i / branches) * math.pi * 2
		local nextAngle = rotation + ((i + 0.72) / branches) * math.pi * 2
		local wave = math.sin(i * 2.71 + elapsed * 0.12) * radius * 0.018
		local branchRadius = radius * 1.08 + wave
		local x1 = x + math.cos(angle) * branchRadius
		local y1 = y + math.sin(angle) * branchRadius
		local x2 = x + math.cos(nextAngle) * branchRadius
		local y2 = y + math.sin(nextAngle) * branchRadius

		surface.SetDrawColor(91, 7, 21, alpha)
		surface.DrawLine(x1, y1, x2, y2)

		-- Каждый третий шип направлен наружу, остальные — к центру.
		local direction = (i % 3 == 0) and 1 or -1
		local thornLength = (7 + (i % 4) * 2) * reveal
		local thornAngle = angle + direction * 0.24
		local baseX = Lerp(0.52, x1, x2)
		local baseY = Lerp(0.52, y1, y2)
		surface.DrawLine(baseX, baseY, baseX + math.cos(thornAngle) * thornLength, baseY + math.sin(thornAngle) * thornLength)
	end
end

function INTRO:DrawBloodVeins(w, h, elapsed, reveal)
	if (reveal <= 0) then return end

	-- Симметричные тонкие жилы вползают в кадр из верхних углов.
	local depth = h * 0.19 * reveal
	local spread = w * 0.12
	local sway = math.sin(elapsed * 0.22) * 3

	for side = -1, 1, 2 do
		local originX = side < 0 and 0 or w
		local direction = side < 0 and 1 or -1
		local points = {
			{x = originX, y = 0},
			{x = originX + direction * spread * 0.24, y = depth * 0.24},
			{x = originX + direction * spread * 0.42 + sway * side, y = depth * 0.49},
			{x = originX + direction * spread * 0.73, y = depth * 0.72},
			{x = originX + direction * spread, y = depth}
		}

		surface.SetDrawColor(75, 2, 15, 70 * reveal)
		for i = 1, #points - 1 do
			surface.DrawLine(points[i].x, points[i].y, points[i + 1].x, points[i + 1].y)
		end

		for i = 2, 4 do
			local point = points[i]
			local branchLength = 18 + i * 5
			local branchDirection = (i % 2 == 0) and -1 or 1
			surface.DrawLine(point.x, point.y, point.x + direction * branchLength, point.y + branchDirection * branchLength)
		end
	end
end

function INTRO:PaintFrame(frame, w, h)
	local elapsed = RealTime() - frame.startTime

	-- Единая двадцатисекундная драматургия вместо набора одновременно
	-- возникающих декоративных слоёв.
	local backgroundReveal = Phase(elapsed, 0.20, 4.80)
	local atmosphereReveal = Phase(elapsed, 3.20, 4.20)
	local veinReveal = Phase(elapsed, 7.10, 4.00)
	local thornReveal = Phase(elapsed, 9.15, 3.10)
	local titleTimeline = math.max(elapsed - 11.35, 0)
	local subtitleReveal = Phase(elapsed, 13.85, 1.45)
	local descriptionReveal = Phase(elapsed, 15.15, 1.40)
	local lowerOrnamentReveal = Phase(elapsed, 16.35, 1.35)
	local heartbeat = self:GetHeartbeat(elapsed)
	local zoom = Lerp(Clamp01(elapsed / 28), 1.085, 1.018)
	local driftX = math.sin(elapsed * 0.040) * 0.0025
	local driftY = math.cos(elapsed * 0.034) * 0.0015

	-- Фоновый материал, его путь и способ загрузки не изменены.
	if (self.background and !self.background:IsError()) then
		self:DrawCoverMaterial(self.background, w, h, zoom, driftX, driftY)
	else
		surface.SetDrawColor(self.colors.black)
		surface.DrawRect(0, 0, w, h)
	end

	-- Фотография очень медленно выходит из абсолютной темноты.
	surface.SetDrawColor(2, 1, 2, 244 * (1 - backgroundReveal))
	surface.DrawRect(0, 0, w, h)

	-- Современно-готическая палитра: холодный графит, старая слоновая кость,
	-- один глубокий кровавый акцент и никакого неонового свечения.
	surface.SetDrawColor(7, 3, 8, 94)
	surface.DrawRect(0, 0, w, h)
	-- Постоянная цветовая вуаль: сердечный ритм больше не мигает всем экраном.
	surface.SetDrawColor(75, 0, 13, 17)
	surface.DrawRect(0, 0, w, h)
	surface.SetDrawColor(0, 0, 0, 120)
	surface.DrawRect(0, h * 0.61, w, h * 0.39)

	self:DrawRain(frame, w, h, elapsed, atmosphereReveal * 0.72)
	self:DrawRavens(frame, w, h, elapsed, atmosphereReveal)
	self:DrawMotes(frame, w, h, elapsed)
	self:DrawBloodVeins(w, h, elapsed, veinReveal)
	self:DrawVignette(w, h)

	-- Настоящая детализированная готическая резьба появляется лишь после
	-- кровавого удара и остаётся очень тёмным обрамляющим слоем.
	local frameReveal = Phase(elapsed, 8.40, 4.80)
	self:DrawDecor("frame", 0, 0, w, h, Color(151, 132, 126, 34 * frameReveal))

	local centerX = w * 0.5
	local centerY = h * 0.355
	local sealRadius = math.Clamp(h * 0.175, 105, 185)
	local titleSpacing = math.Clamp(w * 0.005, 6, 11)

	-- Роза собора рождается под жидкими нитями и добавляет несколько планов
	-- глубины: фотография → каменная роза → кровь → геометрическая печать.
	local roseReveal = Phase(elapsed, 7.55, 4.10)
	local roseSize = sealRadius * 2.35 * EaseOutCubic(roseReveal)
	self:DrawDecor("rose", centerX, centerY, roseSize, roseSize, Color(111, 17, 32, 31 * roseReveal), -elapsed * 0.42)

	local _, sealBirth = self:DrawBloodGenesis(frame, centerX, centerY, w, h, elapsed)
	self:DrawGlassShards(frame, centerX, centerY, elapsed)

	-- Кровавые нити упорядочиваются в точную геометрию эмблемы.
	self:DrawMasqueradeSeal(centerX, centerY, sealRadius, elapsed, sealBirth, 48 * sealBirth + heartbeat * 5)
	self:DrawThornHalo(centerX, centerY, sealRadius, elapsed, thornReveal, 53 * thornReveal + heartbeat * 3)
	self:DrawCrimsonSigil(centerX, centerY, h, elapsed, heartbeat)

	local upperOrnamentReveal = Phase(elapsed, 10.10, 2.20)
	local upperOrnamentY = h * 0.235
	local upperWidth = math.min(w * 0.32, 520)
	self:DrawOrnament(centerX, upperOrnamentY, upperWidth, 170 * upperOrnamentReveal, upperOrnamentReveal)
	self:DrawBloodDrips(frame, centerX, upperOrnamentY, upperWidth, elapsed - 8.8, upperOrnamentReveal)

	-- Название рождается непосредственно из уже сформированной эмблемы.
	self:DrawSpacedTitle(self.title, "AfterlightIntroTitle", centerX, h * 0.35, titleSpacing, titleTimeline, self.colors.ivory)

	local shine = Phase(elapsed, 13.05, 0.20) * (1 - Phase(elapsed, 13.38, 0.34))
	if (shine > 0) then
		self:DrawSpacedTitle(self.title, "AfterlightIntroTitle", centerX - 1, h * 0.349, titleSpacing, 10, Color(255, 239, 228, 78 * shine))
	end

	draw.SimpleText(self.subtitle, "AfterlightIntroSubtitle", centerX + 1, h * 0.435 + 2, Color(0, 0, 0, 190 * subtitleReveal), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(self.subtitle, "AfterlightIntroSubtitle", centerX, h * 0.435, Alpha(self.colors.bloodBright, 235 * subtitleReveal), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(self.description, "AfterlightIntroText", centerX, h * 0.485, Alpha(self.colors.ivory, 220 * descriptionReveal), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	self:DrawOrnament(centerX, h * 0.545, math.min(w * 0.22, 350), 105 * lowerOrnamentReveal, lowerOrnamentReveal)

	local filmReveal = Phase(elapsed, 3.8, 4.5)
	-- Повреждения плёнки больше не пульсируют яркостью кадра.
	self:DrawDecor("film", 0, 0, w, h, Color(213, 203, 193, 6 * filmReveal))

	-- Кадр раскрывается синхронно с падением капли и полностью открыт к удару.
	self:DrawOpeningShutter(w, h, elapsed)

	-- Едва различимое живое зерно; оно не создаёт плоской дымовой пелены.
	local grainAlpha = 1.5 + math.abs(math.sin(elapsed * 17.31)) * 1.8
	for i = 1, 8 do
		local seed = (i * 173 + math.floor(elapsed * 12) * 37) % 997
		local x = (seed / 997) * w
		local y = ((seed * 31) % 997) / 997 * h
		surface.SetDrawColor(230, 218, 206, grainAlpha)
		surface.DrawRect(x, y, 1, 1)
	end
end

function INTRO:CreateButton(parent)
	local button = vgui.Create("DButton", parent)
	button:SetText("")
	button:SetAlpha(0)
	button:SetEnabled(false)
	button:SetCursor("hand")
	button.hoverFraction = 0
	button.pressFraction = 0
	button.appearedAt = 0

	button.PerformLayout = function(self)
		local width = math.Clamp(ScrW() * 0.22, 320, 410)
		local height = math.Clamp(ScrH() * 0.062, 56, 70)
		self:SetSize(width, height)
		self:SetPos((parent:GetWide() - width) * 0.5, parent:GetTall() * 0.69)
	end

	button.Paint = function(self, w, h)
		local hovered = self:IsHovered() and self:IsEnabled()
		local depressed = self:IsDown() and hovered
		self.hoverFraction = Lerp(math.min(FrameTime() * 8, 1), self.hoverFraction, hovered and 1 or 0)
		self.pressFraction = Lerp(math.min(FrameTime() * 15, 1), self.pressFraction, depressed and 1 or 0)

		local hover = self.hoverFraction
		local press = self.pressFraction
		local cut = math.Clamp(h * 0.19, 9, 13)
		local offsetY = press * 2
		local pulse = 0.5 + math.sin(RealTime() * 1.55) * 0.5

		local function Shape(inset, yOffset)
			return {
				{x = inset + cut, y = inset + yOffset},
				{x = w - inset - cut, y = inset + yOffset},
				{x = w - inset, y = inset + cut + yOffset},
				{x = w - inset, y = h - inset - cut + yOffset},
				{x = w - inset - cut, y = h - inset + yOffset},
				{x = inset + cut, y = h - inset + yOffset},
				{x = inset, y = h - inset - cut + yOffset},
				{x = inset, y = inset + cut + yOffset}
			}
		end

		local function DrawGothicFrame(inset, color, yOffset)
			local points = Shape(inset, yOffset)
			surface.SetDrawColor(color)
			for i = 1, #points do
				local nextIndex = i == #points and 1 or i + 1
				surface.DrawLine(points[i].x, points[i].y, points[nextIndex].x, points[nextIndex].y)
			end
		end

		-- Мягкая глубокая тень вместо яркого интерфейсного glow.
		draw.NoTexture()
		surface.SetDrawColor(0, 0, 0, 105 + hover * 30)
		surface.DrawPoly(Shape(3, 5 + offsetY))

		-- Восьмиугольный силуэт с внутренним кровавым слоем.
		surface.SetDrawColor(11 + hover * 12, 6, 9, 225 + hover * 20)
		surface.DrawPoly(Shape(1, offsetY))
		surface.SetDrawColor(69 + hover * 35, 3, 16, 70 + hover * 58)
		surface.DrawPoly(Shape(7, offsetY))

		DrawGothicFrame(1, Color(100 + hover * 75, 9 + hover * 12, 28 + hover * 18, 225), offsetY)
		DrawGothicFrame(6, Color(157, 139, 133, 38 + hover * 58), offsetY)

		-- Центральная ось и два ромба связывают кнопку с основной эмблемой.
		local wing = Lerp(hover, w * 0.12, w * 0.23)
		local centerX = w * 0.5
		local centerY = h * 0.5 + offsetY
		surface.SetDrawColor(139, 14, 35, 85 + hover * 85)
		surface.DrawLine(centerX - wing, h - 7 + offsetY, centerX - 10, h - 7 + offsetY)
		surface.DrawLine(centerX + 10, h - 7 + offsetY, centerX + wing, h - 7 + offsetY)

		for side = -1, 1, 2 do
			local diamondX = side < 0 and 15 or w - 15
			draw.NoTexture()
			surface.SetDrawColor(145 + hover * 34, 15, 37, 145 + hover * 70)
			surface.DrawPoly({
				{x = diamondX, y = centerY - 5 - hover * 2},
				{x = diamondX + 5 + hover * 2, y = centerY},
				{x = diamondX, y = centerY + 5 + hover * 2},
				{x = diamondX - 5 - hover * 2, y = centerY}
			})
		end

		-- Узкий световой след идёт только по рамке и ускоряется при наведении.
		local travel = ((RealTime() * (0.10 + hover * 0.22)) % 1)
		local glintX = Lerp(travel, cut + 12, w - cut - 40)
		surface.SetDrawColor(226, 202, 192, (14 + hover * 64) * (0.7 + pulse * 0.3))
		surface.DrawLine(glintX, 1 + offsetY, glintX + 28, 1 + offsetY)

		local textColor = Color(
			Lerp(hover, 207, 239),
			Lerp(hover, 197, 220),
			Lerp(hover, 191, 214),
			255
		)
		draw.SimpleText(INTRO.buttonText, "AfterlightIntroButton", centerX, centerY - 1, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		-- Подсказка реакции: тонкий кровавый штрих расширяется вместе с hover.
		surface.SetDrawColor(174, 18, 42, 105 * hover)
		surface.DrawRect(centerX - wing * 0.58, h - 4 + offsetY, wing * 1.16, 1)
	end

	button.DoClick = function(self)
		if (!self:IsEnabled()) then return end
		INTRO:Close()
	end

	button:InvalidateLayout(true)

	timer.Create(self.timerButton, self.buttonDelay, 1, function()
		if (!IsValid(button) or !INTRO.active or INTRO.closing) then return end

		button.appearedAt = RealTime()
		button:SetEnabled(true)
		button:AlphaTo(255, 0.85, 0)
	end)

	return button
end

function INTRO:Close(immediate)
	if (!self.active or self.closing) then return end

	self.closing = true
	timer.Remove(self.timerButton)

	if (IsValid(self.button)) then
		self.button:SetEnabled(false)
	end

	-- Музыкальный контекст удерживается до конца затухания: меню персонажей
	-- появляется в тот же момент, и трек идёт без разрыва и перезапуска.
	local function Finish()
		if (IsValid(INTRO.frame)) then
			INTRO.frame:Remove()
		end

		INTRO.frame = nil
		INTRO.button = nil
		INTRO.active = false
		INTRO.closing = false
		INTRO:SetCharacterMenuVisible(true)
		SetMusicContext(false)
		hook.Remove("Think", INTRO.hookMenu)
	end

	if (immediate or !IsValid(self.frame)) then
		Finish()
	else
		self.frame:AlphaTo(0, self.fadeOutDuration, 0, Finish)
	end
end

function INTRO:Open()
	if (self.shown or self.active) then return end

	self.active = true
	self.shown = true
	self.closing = false

	SetMusicContext(true)

	self:SetCharacterMenuVisible(false)

	hook.Add("Think", self.hookMenu, function()
		if (INTRO.active) then
			INTRO:SetCharacterMenuVisible(false)
		end
	end)

	local frame = vgui.Create("DFrame")
	if (!IsValid(frame)) then
		self.active = false
		self.shown = false
		return
	end

	frame:SetSize(ScrW(), ScrH())
	frame:SetPos(0, 0)
	frame:SetZPos(1000000)
	frame:SetTitle("")
	frame:ShowCloseButton(false)
	frame:SetDraggable(false)
	frame:SetSizable(false)
	frame:SetAlpha(255)
	frame:SetKeyboardInputEnabled(true)
	frame:SetMouseInputEnabled(true)
	frame:MakePopup()
	frame:MoveToFront()
	frame.startTime = RealTime()
	frame.Paint = function(panel, w, h)
		INTRO:PaintFrame(panel, w, h)
	end
	self:BuildAtmosphere(frame)
	self.frame = frame
	self.button = self:CreateButton(frame)

	-- Ползунок громкости заставки размещает музыкальный контроллер: он сам
	-- находит активный экран и наследует его видимость и затухание.

	frame.OnKeyCodePressed = function(_, key)
		if ((key == KEY_ESCAPE or key == KEY_SPACE or key == KEY_ENTER) and IsValid(INTRO.button) and INTRO.button:IsEnabled()) then
			INTRO.button:DoClick()
		end
	end

	timer.Simple(0.1, function()
		if (IsValid(INTRO.curtain)) then
			INTRO.curtain:Remove()
			INTRO.curtain = nil
		end
	end)
end

function INTRO:TryLoadMaterial(attempt, generation)
	if (generation != self.loadGeneration) then return end

	self.background = Material(self.backgroundPath, "smooth noclamp")
	self:LoadDecorMaterials()

	if (!self.background:IsError() or attempt >= self.materialAttempts) then
		self:Open()
		return
	end

	timer.Create(self.timerMaterial, self.materialRetryDelay, 1, function()
		if (generation == INTRO.loadGeneration) then
			INTRO:TryLoadMaterial(attempt + 1, generation)
		end
	end)
end

function INTRO:Start()
	if (self.shown or self.active) then return end

	self.loadGeneration = self.loadGeneration + 1
	self:CreateCurtain()
	self:TryLoadMaterial(1, self.loadGeneration)
end

function INTRO:Destroy()
	self.loadGeneration = self.loadGeneration + 1
	timer.Remove(self.timerAutoStart)
	timer.Remove(self.timerButton)
	timer.Remove(self.timerMaterial)
	hook.Remove("Think", self.hookMenu)

	if (IsValid(self.frame)) then self.frame:Remove() end
	if (IsValid(self.curtain)) then self.curtain:Remove() end

	self.frame = nil
	self.curtain = nil
	self.button = nil
	self.active = false
	self.closing = false

	-- Заставка больше не существует — музыкальный запрос снимаем сразу.
	SetMusicContext(false)
end

-- Безопасная очистка после hot reload старой версии файла.
timer.Remove(INTRO.timerAutoStart)
timer.Remove(INTRO.timerButton)
timer.Remove(INTRO.timerMaterial)
hook.Remove("Think", INTRO.hookMenu)
hook.Remove("OnScreenSizeChanged", INTRO.hookResolution)

INTRO:CreateFonts()
INTRO:CreateCurtain()

hook.Add("OnScreenSizeChanged", INTRO.hookResolution, function()
	INTRO:CreateFonts()

	if (IsValid(INTRO.frame)) then
		INTRO.frame:SetSize(ScrW(), ScrH())
		INTRO.frame:InvalidateLayout(true)

		if (IsValid(INTRO.button)) then
			INTRO.button:InvalidateLayout(true)
		end
	end

	if (IsValid(INTRO.curtain)) then
		INTRO.curtain:SetSize(ScrW(), ScrH())
	end
end)

timer.Create(INTRO.timerAutoStart, 0.05, 1, function()
	INTRO:Start()
end)

-- Оставлено в пространстве имён проекта для отладки/принудительного закрытия.
AfterlightIntro = INTRO
