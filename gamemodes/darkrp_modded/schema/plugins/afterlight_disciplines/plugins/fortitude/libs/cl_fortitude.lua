local PLUGIN = PLUGIN

ix.fortitude = ix.fortitude or {}

-- Слои экранной «каменной» ауры: fx_a — треснувшая каменная кайма по краям,
-- fx_b — медленная рябь каменных колец поверх. Прозрачность запечена в png.
local fxMaterialA = Material("afterlight/disciplines/fortitude/fortitude_fx_a.png", "smooth noclamp")
local fxMaterialB = Material("afterlight/disciplines/fortitude/fortitude_fx_b.png", "smooth noclamp")
local frameMaterial = Material("afterlight/disciplines/fortitude/shield_frame.png", "smooth noclamp")

local function CreateFonts()
	local scale = math.Clamp(ScrH() / 1080, 0.72, 1.35)
	surface.CreateFont("AfterlightFortitudeValue", {
		font = "Georgia", size = math.floor(17 * scale), weight = 700,
		extended = true, antialias = true
	})
	surface.CreateFont("AfterlightFortitudeCaption", {
		font = "Times New Roman", size = math.floor(12 * scale), weight = 600,
		extended = true, antialias = true
	})
end
CreateFonts()
hook.Add("OnScreenSizeChanged", "AfterlightFortitudeFonts", CreateFonts)

-- === Звук активации: один файл, по переходу 0 -> N ===
local lastActiveLevel = 0

local function UpdateSound(client)
	local level = PLUGIN:GetActiveLevel(client)
	if (level > 0 and lastActiveLevel == 0) then
		sound.PlayFile("sound/" .. ix.fortitude.SOUND_PATH, "noplay noblock", function(channel)
			if (IsValid(channel)) then
				channel:SetVolume(ix.fortitude.SOUND_VOLUME or 0.9)
				channel:Play()
			end
		end)
	end
	lastActiveLevel = level
end

-- === Каменная рябь на время действия ===
local auraAlpha = 0

local function DrawStoneAura(client)
	local level = PLUGIN:GetActiveLevel(client)
	auraAlpha = Lerp(math.min(FrameTime() * 3, 1), auraAlpha, level > 0 and 1 or 0)
	if (auraAlpha < 0.01) then return end

	-- Медленное «дыхание» камня: кайма и рябь пульсируют в противофазе.
	local pulse = 0.75 + math.sin(RealTime() * 2.1) * 0.25

	surface.SetMaterial(fxMaterialA)
	surface.SetDrawColor(255, 255, 255, 210 * auraAlpha * pulse)
	surface.DrawTexturedRect(0, 0, ScrW(), ScrH())

	surface.SetMaterial(fxMaterialB)
	surface.SetDrawColor(255, 255, 255, 130 * auraAlpha * (1.25 - pulse * 0.5))
	surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
end

-- === Индикатор барьера: оранжевая полоска в готической рамке, снизу слева ===
local function DrawShieldHUD(client)
	local maximum = client:GetNW2Int("afterlightFortitudeMax", 0)
	if (maximum <= 0) then return end
	local current = client:GetNW2Int("afterlightFortitudeShield", 0)

	local scale = math.Clamp(ScrH() / 1080, 0.72, 1.35)
	local w, h = 340 * scale, 78 * scale
	local x = 18 * scale
	local y = ScrH() - h - 62 * scale

	-- Канал полоски (рамка ляжет сверху, сердцевица прозрачна).
	-- Тёмная подложка внутри рамки: подписи читаемы и на светлой сцене.
	draw.RoundedBox(6, x + w * 0.02, y + h * 0.08, w * 0.96, h * 0.84, Color(10, 7, 4, 200))

	local insetX, channelW = w * 0.07, w * 0.86
	local channelY, channelH = y + h * 0.40, h * 0.26
	draw.RoundedBox(4, x + insetX, channelY, channelW, channelH, Color(6, 4, 2, 225))

	-- Янтарный «раскалённый камень»: вертикальные полосы как у индикатора
	-- крови, но в оранжевой гамме Стойкости.
	local filled = channelW * math.Clamp(current / maximum, 0, 1)
	if (filled > 0) then
		for i = 0, 11 do
			local t = i / 11
			local stripX = x + insetX + i * channelW / 12
			local left = math.min(channelW / 12 + 1, math.max(0, x + insetX + filled - stripX))
			if (left > 0) then
				local r = 176 + math.sin(t * math.pi) * 72
				local g = 84 + math.sin(t * math.pi) * 52
				surface.SetDrawColor(r, g, 22, 235)
				surface.DrawRect(stripX, channelY, left, channelH)
			end
		end
		-- Светлая кромка «жидкости».
		surface.SetDrawColor(255, 176, 92, 150)
		surface.DrawRect(x + insetX + 1, channelY, math.max(1, filled - 2), math.max(1, channelH * 0.12))
	end

	-- Готическая рамка поверх канала.
	surface.SetMaterial(frameMaterial)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawTexturedRect(x, y, w, h)

	draw.SimpleText("ЩИТ СТОЙКОСТИ", "AfterlightFortitudeCaption",
		x + w * 0.5, y + h * 0.17, Color(224, 158, 84, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(string.format("%d / %d", current, maximum), "AfterlightFortitudeValue",
		x + w * 0.5, y + h * 0.80, Color(242, 205, 156), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local nextHUDError = 0

hook.Add("HUDPaint", "AfterlightFortitudeHUD", function()
	if (IsValid(ix.gui.characterMenu) or IsValid(ix.gui.menu)) then return end
	local client = LocalPlayer()
	local character = IsValid(client) and client:GetCharacter()
	if (!character or !character.IsVampire or !character:IsVampire()) then return end

	-- Декоративный HUD не должен рвать общую цепочку HUDPaint.
	local success, reason = pcall(function()
		UpdateSound(client)
		DrawStoneAura(client)
		DrawShieldHUD(client)
	end)
	if (!success and RealTime() >= nextHUDError) then
		nextHUDError = RealTime() + 5
		ErrorNoHalt("[Afterlight Fortitude] HUD render error: " .. tostring(reason) .. "\n")
	end
end)
