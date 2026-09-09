if (!CLIENT) then return end

local iconMaterials = {}
local hudFrameMaterial = Material("afterlight/disciplines/hud_frame.png", "smooth noclamp")

ix.option.Add("disciplineHUDScale", ix.type.number, 1, {category = "Дисциплины HUD", min = 0.75, max = 1.3, decimals = 2})
ix.option.Add("disciplineHUDRightMargin", ix.type.number, 155, {category = "Дисциплины HUD", min = 20, max = 420, decimals = 0})
ix.option.Add("disciplineHUDBottomMargin", ix.type.number, 38, {category = "Дисциплины HUD", min = 0, max = 260, decimals = 0})

local function CreateFonts()
	local scale = math.Clamp(ScrH() / 900, 0.78, 1.35)
	surface.CreateFont("AfterlightDisciplinePower", {
		font = "Cormorant Garamond", size = math.floor(14 * scale), weight = 700,
		extended = true, antialias = true
	})
	surface.CreateFont("AfterlightDisciplineCooldown", {
		font = "Cormorant Garamond", size = math.floor(22 * scale), weight = 800,
		extended = true, antialias = true
	})
end
CreateFonts()
hook.Add("OnScreenSizeChanged", "AfterlightDisciplineHUDFonts", CreateFonts)

local function GetIcon(path)
	if (!isstring(path) or path == "") then return nil end
	if (iconMaterials[path] == nil) then
		local material = Material(path, "smooth noclamp")
		iconMaterials[path] = !material:IsError() and material or false
	end
	return iconMaterials[path] or nil
end

local function DrawCorner(x, y, size, flipX, flipY, alpha)
	local sx, sy = flipX and -1 or 1, flipY and -1 or 1
	surface.SetDrawColor(147, 39, 53, alpha)
	surface.DrawLine(x, y, x + sx * size, y)
	surface.DrawLine(x, y, x, y + sy * size)
	surface.SetDrawColor(71, 58, 61, alpha * 0.9)
	surface.DrawLine(x + sx * 3, y + sy * 3, x + sx * (size - 5), y + sy * 3)
	surface.DrawLine(x + sx * 3, y + sy * 3, x + sx * 3, y + sy * (size - 5))
end

local function DrawCooldownTicks(cx, cy, radius, fraction, scale)
	local activeTicks = math.ceil(math.Clamp(fraction, 0, 1) * 20)
	for index = 1, 20 do
		local angle = math.rad(-90 + (index - 1) * 18)
		local inner = radius - 2 * scale
		local outer = radius + (index % 5 == 1 and 5 or 3) * scale
		local color = index <= activeTicks and Color(213, 44, 59, 235) or Color(54, 40, 43, 150)
		surface.SetDrawColor(color)
		surface.DrawLine(cx + math.cos(angle) * inner, cy + math.sin(angle) * inner,
			cx + math.cos(angle) * outer, cy + math.sin(angle) * outer)
	end
end

local function DrawDisciplineHUD(character)
	local power, selected = ix.disciplines.GetSelectedPower(character)
	local discipline = selected and ix.disciplines.GetInterfaceDiscipline(selected.disciplineID) or nil
	local scale = ix.option.Get("disciplineHUDScale", 1)
	local frame = math.floor(78 * scale)
	local textHeight = power and math.floor(24 * scale) or 0
	local right = ix.option.Get("disciplineHUDRightMargin", 155)
	local bottom = ix.option.Get("disciplineHUDBottomMargin", 38)
	local x = ScrW() - right - frame
	local y = ScrH() - bottom - textHeight - frame
	local cx, cy = x + frame * 0.5, y + frame * 0.5

	-- Compact reliquary: blackened metal, restrained silver and crimson accents.
	draw.RoundedBox(7 * scale, x - 5 * scale, y - 5 * scale, frame + 10 * scale,
		frame + 10 * scale, Color(2, 2, 3, 232))
	surface.SetDrawColor(39, 31, 34, 245)
	surface.DrawRect(x, y, frame, frame)
	surface.SetDrawColor(7, 6, 8, 255)
	surface.DrawRect(x + 3 * scale, y + 3 * scale, frame - 6 * scale, frame - 6 * scale)
	surface.SetDrawColor(115, 20, 36, 220)
	surface.DrawOutlinedRect(x + 2 * scale, y + 2 * scale, frame - 4 * scale, frame - 4 * scale, 1)
	surface.SetDrawColor(89, 80, 79, 175)
	surface.DrawOutlinedRect(x + 6 * scale, y + 6 * scale, frame - 12 * scale, frame - 12 * scale, 1)
	DrawCorner(x, y, 19 * scale, false, false, 225)
	DrawCorner(x + frame, y, 19 * scale, true, false, 225)
	DrawCorner(x, y + frame, 19 * scale, false, true, 225)
	DrawCorner(x + frame, y + frame, 19 * scale, true, true, 225)

	surface.SetMaterial(hudFrameMaterial)
	surface.SetDrawColor(185, 160, 157, 155)
	surface.DrawTexturedRect(x - 7 * scale, y - 7 * scale, frame + 14 * scale, frame + 14 * scale)

	draw.NoTexture()
	surface.SetDrawColor(3, 3, 4, 248)
	surface.DrawCircle(cx, cy, frame * 0.34, 3, 3, 4, 248)
	surface.DrawCircle(cx, cy, frame * 0.36, 119, 22, 38, 205)
	surface.DrawCircle(cx, cy, frame * 0.39, 61, 52, 54, 180)

	local icon = discipline and GetIcon(discipline.icon) or nil
	if (!icon and power) then icon = GetIcon(power.icon) end
	if (icon) then
		surface.SetMaterial(icon)
		surface.SetDrawColor(229, 216, 207, 255)
		surface.DrawTexturedRect(cx - frame * 0.28, cy - frame * 0.28, frame * 0.56, frame * 0.56)
	end

	local cooldown = power and ix.disciplines.GetClientCooldown and ix.disciplines.GetClientCooldown(power.disciplineID, power.id) or 0
	if (cooldown > 0) then
		local total = math.max(tonumber(power.cooldown) or cooldown, 0.01)
		DrawCooldownTicks(cx, cy, frame * 0.43, cooldown / total, scale)
		draw.RoundedBox(frame * 0.5, x + 8 * scale, y + 8 * scale, frame - 16 * scale,
			frame - 16 * scale, Color(2, 1, 3, 188))
		draw.SimpleText(tostring(math.ceil(cooldown)), "AfterlightDisciplineCooldown", cx + 1, cy + 2,
			Color(15, 2, 4, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(tostring(math.ceil(cooldown)), "AfterlightDisciplineCooldown", cx, cy,
			Color(226, 57, 69, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	if (power) then
		local textY = y + frame + 6 * scale
		draw.SimpleText(power.name, "AfterlightDisciplinePower", cx + 1, textY + 1,
			Color(4, 2, 3, 245), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		draw.SimpleText(power.name, "AfterlightDisciplinePower", cx, textY,
			Color(222, 209, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end
end

local nextError = 0
hook.Add("HUDPaint", "AfterlightDisciplineHUD", function()
	if (IsValid(ix.gui.afterlightDisciplineWheel) or IsValid(ix.gui.menu) or IsValid(ix.gui.characterMenu)) then return end
	local client = LocalPlayer()
	local character = IsValid(client) and client:GetCharacter()
	if (!character or !character.IsVampire or !character:IsVampire()) then return end
	local success, reason = pcall(DrawDisciplineHUD, character)
	if (!success and RealTime() >= nextError) then
		nextError = RealTime() + 5
		ErrorNoHalt("[Afterlight Discipline Interface] HUD error: " .. tostring(reason) .. "\n")
	end
end)

concommand.Add("afterlight_discipline_hud_debug", function()
	local character = IsValid(LocalPlayer()) and LocalPlayer():GetCharacter()
	print("[Afterlight Discipline Interface] HUD hook:", hook.GetTable().HUDPaint and hook.GetTable().HUDPaint.AfterlightDisciplineHUD != nil)
	print("[Afterlight Discipline Interface] Character:", character and character:GetID() or "none",
		"vampire:", character and character.IsVampire and character:IsVampire() or false)
	print("[Afterlight Discipline Interface] HUD material error:", hudFrameMaterial:IsError(),
		"right:", ix.option.Get("disciplineHUDRightMargin", 155), "bottom:", ix.option.Get("disciplineHUDBottomMargin", 38))
end)

print("[Afterlight Discipline Interface] ornate HUD module loaded from derma/cl_hud.lua")
