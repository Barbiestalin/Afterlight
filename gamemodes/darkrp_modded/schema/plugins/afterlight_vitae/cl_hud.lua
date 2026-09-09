if (!CLIENT) then return end

local frameMaterial = Material("afterlight/vitae/frame.png", "smooth noclamp")
local displayValue, pulseStarted, pulseDirection, pulseSource = nil, -100, 0, ""
local authoritativeValue, authoritativeMaximum, activeCharacterID

ix.option.Add("vitaeHUDScale", ix.type.number, 1, {
	category = "Витэ HUD", min = 0.75, max = 1.3, decimals = 2
})
ix.option.Add("vitaeHUDRightMargin", ix.type.number, 22, {
	category = "Витэ HUD", min = 0, max = 240, decimals = 0
})
ix.option.Add("vitaeHUDVerticalOffset", ix.type.number, 0, {
	category = "Витэ HUD", min = -240, max = 240, decimals = 0
})

local function CreateFonts()
	local scale = math.Clamp(ScrH() / 1080, 0.72, 1.35)
	surface.CreateFont("AfterlightVitaeValue", {
		font = "Georgia", size = math.floor(18 * scale), weight = 700,
		extended = true, antialias = true
	})
	surface.CreateFont("AfterlightVitaeCaption", {
		font = "Times New Roman", size = math.floor(11 * scale), weight = 500,
		extended = true, antialias = true
	})
end
CreateFonts()
hook.Add("OnScreenSizeChanged", "AfterlightVitaeFonts", CreateFonts)

net.Receive("AfterlightVitaeChanged", function()
	local oldValue = net.ReadUInt(8)
	local newValue = net.ReadUInt(8)
	authoritativeMaximum = net.ReadUInt(8)
	pulseSource = net.ReadString()
	pulseStarted = CurTime()
	pulseDirection = newValue > oldValue and 1 or -1
	authoritativeValue = newValue
	displayValue = displayValue or oldValue
end)

local function DrawLiquid(x, y, w, h, fraction, alpha, pulse)
	draw.RoundedBox(math.max(2, w * 0.28), x, y, w, h, Color(4, 0, 2, 235 * alpha))

	-- Horizontal and vertical insets are intentionally independent. The old
	-- one-pixel minimum consumed too much of this narrow channel and left the
	-- blood visibly recessed from both inner frame edges.
	local verticalInset = math.max(1, w * 0.11)
	local horizontalInset = math.max(0.25, w * 0.015)
	local filled = math.max(0, (h - verticalInset * 2) * fraction)
	if (filled <= 0) then return end
	local fy = y + h - verticalInset - filled
	local innerX, innerW = x + horizontalInset, w - horizontalInset * 2

	-- Layered crimson glass instead of a flat red rectangle.
	for i = 0, 11 do
		local t = i / 11
		local stripW = math.ceil(innerW / 12) + 1
		local r = 72 + math.sin(t * math.pi) * 82
		local g = 1 + math.sin(t * math.pi) * 12
		surface.SetDrawColor(r, g, 12, (220 + pulse * 30) * alpha)
		surface.DrawRect(innerX + i * innerW / 12, fy, stripW, filled)
	end

	-- Stable liquid edge: only the complete column changes height. The previous
	-- independent bobbing line made value changes look disconnected from fill.
	surface.SetDrawColor(232, 32, 49, (145 + pulse * 90) * alpha)
	surface.DrawRect(innerX + 1, fy, innerW - 2, math.max(1, h * 0.006))
	surface.SetDrawColor(255, 112, 121, (45 + pulse * 65) * alpha)
	surface.DrawRect(innerX + innerW * 0.24, fy + 3, math.max(1, innerW * 0.09), math.max(0, filled - 7))

	-- Subtle bubbles become more visible during replenishment.
	local bubbleAlpha = (25 + pulse * 105) * alpha
	for i = 1, 5 do
		local seed = i * 1.731
		local bx = innerX + innerW * (0.22 + (math.sin(seed * 4.1) + 1) * 0.27)
		local travel = (CurTime() * (7 + i * 1.7) + i * 31) % math.max(filled, 1)
		local by = y + h - 4 - travel
		if (by >= fy + 4) then
			-- surface.DrawCircle expects numeric RGBA arguments, not a Color table.
			-- Passing Color(...) raised inside HUDPaint and could abort later hooks,
			-- including Helix's stock health and stamina bars.
			surface.DrawCircle(bx, by, math.max(1, w * (0.025 + i * 0.004)),
				248, 82, 96, math.Clamp(math.floor(bubbleAlpha), 0, 255))
		end
	end
end

local function DrawVitaeHUD(character)
	local characterID = character:GetID()
	if (activeCharacterID != characterID) then
		activeCharacterID = characterID
		authoritativeValue, authoritativeMaximum = nil, nil
		displayValue = nil
	end

	local maximum = ix.vitae.GetMax(character)
	if (maximum <= 0) then maximum = authoritativeMaximum or 0 end
	if (maximum <= 0) then return end
	local synchronized = ix.vitae.Get(character)
	local actual = authoritativeValue != nil and math.Clamp(authoritativeValue, 0, maximum) or synchronized
	if (authoritativeValue != nil and synchronized == authoritativeValue) then
		actual = synchronized
		authoritativeValue, authoritativeMaximum = nil, nil
	end
	displayValue = displayValue or actual
	displayValue = Lerp(math.min(FrameTime() * 4.8, 1), displayValue, actual)

	local scale = ix.option.Get("vitaeHUDScale", 1)
	local h = math.Clamp(ScrH() * 0.42, 300, 460) * scale
	local w = h * math.max(frameMaterial:Width(), 1) / math.max(frameMaterial:Height(), 1)
	local right = ix.option.Get("vitaeHUDRightMargin", 22)
	local vertical = ix.option.Get("vitaeHUDVerticalOffset", 0)
	local x = ScrW() - w - right
	local y = ScrH() * 0.5 - h * 0.5 + vertical
	local duration = math.max(ix.config.Get("vitaePulseDuration", 1.4), 0.2)
	local pulseFraction = math.Clamp(1 - (CurTime() - pulseStarted) / duration, 0, 1)
	local pulse = math.sin(pulseFraction * math.pi) * pulseFraction
	local gain = pulseDirection > 0
	local glowColor = gain and Color(220, 12, 38) or Color(104, 3, 20)

	-- Local aura; no full-screen heartbeat flash.
	if (pulse > 0.01) then
		for i = 4, 1, -1 do
			local expand = i * 2.5 * scale
			surface.SetMaterial(frameMaterial)
			surface.SetDrawColor(glowColor.r, glowColor.g, glowColor.b, pulse * (13 + i * 7))
			surface.DrawTexturedRect(x - expand, y - expand, w + expand * 2, h + expand * 2)
		end
	end

	-- The frame's inner hairlines occupy x=59..101 of the 160 px source.
	-- 0.375..0.625 places the channel flush against their inner edges without
	-- bleeding across the metal rails.
	local channelX = x + w * 0.375
	local channelY = y + h * 0.073
	local channelW = w * 0.250
	local channelH = h * 0.850
	DrawLiquid(channelX, channelY, channelW, channelH,
		math.Clamp(displayValue / maximum, 0, 1), 1, gain and pulse or pulse * 0.35)

	surface.SetMaterial(frameMaterial)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawTexturedRect(x, y, w, h)

	local textY = y - 8 * scale
	draw.SimpleText(string.format("%d/%d", actual, maximum), "AfterlightVitaeValue",
		x + w * 0.5, textY, Color(232, 213, 202), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
	draw.SimpleText("ВИТЭ", "AfterlightVitaeCaption", x + w * 0.5, textY - 23 * scale,
		Color(132, 94, 92, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
end

local nextHUDError = 0

hook.Add("HUDPaint", "AfterlightVitaeHUD", function()
	if (!ix.config.Get("vitaeHUDEnabled", true)) then return end
	if (IsValid(ix.gui.characterMenu) or IsValid(ix.gui.menu)) then return end
	local client = LocalPlayer()
	local character = IsValid(client) and client:GetCharacter()
	if (!ix.vitae.IsVampire(character)) then displayValue = nil return end

	-- A decorative HUD must never interrupt the shared HUDPaint chain. Keep any
	-- future material/rendering fault local so stock Helix HP/stamina still draw.
	local success, reason = pcall(DrawVitaeHUD, character)
	if (!success and RealTime() >= nextHUDError) then
		nextHUDError = RealTime() + 5
		ErrorNoHalt("[Afterlight Vitae] HUD render error: " .. tostring(reason) .. "\n")
	end
end)
