if (!CLIENT) then return end

local iconMaterials = {}
local hudFrameMaterial = Material("afterlight/disciplines/hud_frame.png", "smooth noclamp")

ix.option.Add("disciplineHUDScale", ix.type.number, 1, {
	category = "Дисциплины HUD", min = 0.75, max = 1.3, decimals = 2
})
ix.option.Add("disciplineHUDRightMargin", ix.type.number, 155, {
	category = "Дисциплины HUD", min = 20, max = 420, decimals = 0
})
ix.option.Add("disciplineHUDBottomMargin", ix.type.number, 38, {
	category = "Дисциплины HUD", min = 0, max = 260, decimals = 0
})

local function CreateFonts()
	local scale = math.Clamp(ScrH() / 1080, 0.72, 1.35)
	surface.CreateFont("AfterlightDisciplineLogo", {
		font = "Georgia", size = math.floor(34 * scale), weight = 800,
		extended = true, antialias = true
	})
	surface.CreateFont("AfterlightDisciplineName", {
		font = "Georgia", size = math.floor(15 * scale), weight = 700,
		extended = true, antialias = true
	})
	surface.CreateFont("AfterlightDisciplinePower", {
		font = "Times New Roman", size = math.floor(14 * scale), weight = 600,
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

local function Monogram(name)
	name = string.Trim(tostring(name or "?"))
	if (utf8 and utf8.offset) then
		local second = utf8.offset(name, 2)
		return string.sub(name, 1, (second or (#name + 1)) - 1)
	end
	return string.sub(name, 1, 1)
end

local function DrawCorner(x, y, size, flipX, flipY, alpha)
	local sx, sy = flipX and -1 or 1, flipY and -1 or 1
	surface.SetDrawColor(185, 42, 58, alpha)
	surface.DrawLine(x, y, x + sx * size, y)
	surface.DrawLine(x, y, x, y + sy * size)
	surface.DrawLine(x + sx * 3, y + sy * 3, x + sx * (size - 4), y + sy * 3)
	surface.DrawLine(x + sx * 3, y + sy * 3, x + sx * 3, y + sy * (size - 4))
end

local function DrawDisciplineHUD(character)
	local power, selected = ix.disciplines.GetSelectedPower(character)
	local discipline = selected and ix.disciplines.Get(selected.disciplineID) or nil
	local scale = ix.option.Get("disciplineHUDScale", 1)
	local frame = math.floor(112 * scale)
	local plaqueWidth = math.floor(210 * scale)
	local plaqueHeight = math.floor(48 * scale)
	local right = ix.option.Get("disciplineHUDRightMargin", 155)
	local bottom = ix.option.Get("disciplineHUDBottomMargin", 38)
	local x = ScrW() - right - frame
	local y = ScrH() - bottom - plaqueHeight - frame

	-- Dark Bloodlines-like socket with the same crimson metal language as VTM UI.
	draw.RoundedBox(8 * scale, x - 5 * scale, y - 5 * scale, frame + 10 * scale,
		frame + 10 * scale, Color(3, 2, 3, 238))
	surface.SetDrawColor(100, 7, 24, 245)
	surface.DrawRect(x, y, frame, frame)
	surface.SetDrawColor(13, 10, 11, 255)
	surface.DrawRect(x + 5 * scale, y + 5 * scale, frame - 10 * scale, frame - 10 * scale)
	surface.SetDrawColor(175, 24, 43, 220)
	surface.DrawOutlinedRect(x + 3 * scale, y + 3 * scale, frame - 6 * scale, frame - 6 * scale, 1)
	DrawCorner(x, y, 22 * scale, false, false, 235)
	DrawCorner(x + frame, y, 22 * scale, true, false, 235)
	DrawCorner(x, y + frame, 22 * scale, false, true, 235)
	DrawCorner(x + frame, y + frame, 22 * scale, true, true, 235)
	surface.SetMaterial(hudFrameMaterial)
	surface.SetDrawColor(255, 255, 255, 245)
	surface.DrawTexturedRect(x - 8 * scale, y - 8 * scale, frame + 16 * scale, frame + 16 * scale)

	local icon = discipline and GetIcon(discipline.icon) or nil
	if (!icon and power) then icon = GetIcon(power.icon) end
	if (icon) then
		surface.SetMaterial(icon)
		surface.SetDrawColor(235, 225, 218, 255)
		surface.DrawTexturedRect(x + 13 * scale, y + 13 * scale, frame - 26 * scale, frame - 26 * scale)
	else
		draw.SimpleText(Monogram(discipline and discipline.name or "Д"), "AfterlightDisciplineLogo",
			x + frame * 0.5, y + frame * 0.5, Color(215, 205, 195), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	local plaqueX = x + frame * 0.5 - plaqueWidth * 0.5
	local plaqueY = y + frame + 8 * scale
	draw.RoundedBox(4 * scale, plaqueX, plaqueY, plaqueWidth, plaqueHeight, Color(4, 3, 4, 230))
	surface.SetDrawColor(130, 12, 30, 220)
	surface.DrawOutlinedRect(plaqueX, plaqueY, plaqueWidth, plaqueHeight, 1)
	draw.SimpleText(discipline and discipline.name or "ДИСЦИПЛИНЫ", "AfterlightDisciplineName",
		plaqueX + plaqueWidth * 0.5, plaqueY + 5 * scale, Color(176, 122, 122),
		TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	draw.SimpleText(power and power.name or "Способность не выбрана", "AfterlightDisciplinePower",
		plaqueX + plaqueWidth * 0.5, plaqueY + 24 * scale, Color(235, 224, 215),
		TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
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
