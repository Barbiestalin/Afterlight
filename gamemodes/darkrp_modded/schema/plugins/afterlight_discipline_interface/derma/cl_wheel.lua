if (!CLIENT) then return end

local wheelBackground = Material("afterlight/disciplines/wheel_background.png", "smooth noclamp")
local iconMaterials = {}

local function CreateFonts()
	local scale = math.Clamp(ScrH() / 900, 0.78, 1.35)
	local family = "Cormorant Garamond"
	surface.CreateFont("AfterlightWheelTitle", {font = family, size = math.floor(27 * scale), weight = 800, extended = true, antialias = true})
	surface.CreateFont("AfterlightWheelDiscipline", {font = family, size = math.floor(17 * scale), weight = 700, extended = true, antialias = true})
	surface.CreateFont("AfterlightWheelPower", {font = family, size = math.floor(16 * scale), weight = 600, extended = true, antialias = true})
	surface.CreateFont("AfterlightWheelSmall", {font = family, size = math.floor(12 * scale), weight = 500, extended = true, antialias = true})
	surface.CreateFont("AfterlightWheelRoman", {font = family, size = math.floor(11 * scale), weight = 700, extended = true, antialias = true})
end
CreateFonts()
hook.Add("OnScreenSizeChanged", "AfterlightDisciplineWheelFonts", CreateFonts)

local function GetIcon(path)
	if (!isstring(path) or path == "") then return nil end
	if (iconMaterials[path] == nil) then
		local material = Material(path, "smooth noclamp")
		iconMaterials[path] = !material:IsError() and material or false
	end
	return iconMaterials[path] or nil
end

local function DrawIcon(material, x, y, size, color)
	if (!material) then return end
	surface.SetMaterial(material)
	surface.SetDrawColor(color or color_white)
	surface.DrawTexturedRect(x - size * 0.5, y - size * 0.5, size, size)
end

local function DrawWedge(cx, cy, innerRadius, outerRadius, startAngle, endAngle, color)
	local polygon = {}
	local steps = math.max(math.ceil(math.abs(endAngle - startAngle) / 5), 4)
	for index = 0, steps do
		local angle = math.rad(Lerp(index / steps, startAngle, endAngle))
		polygon[#polygon + 1] = {x = cx + math.cos(angle) * outerRadius, y = cy + math.sin(angle) * outerRadius}
	end
	for index = steps, 0, -1 do
		local angle = math.rad(Lerp(index / steps, startAngle, endAngle))
		polygon[#polygon + 1] = {x = cx + math.cos(angle) * innerRadius, y = cy + math.sin(angle) * innerRadius}
	end
	draw.NoTexture()
	surface.SetDrawColor(color)
	surface.DrawPoly(polygon)
end

local function DrawRing(cx, cy, radius, color, repeats)
	repeats = repeats or 1
	for offset = 0, repeats - 1 do
		surface.DrawCircle(cx, cy, radius + offset, color.r, color.g, color.b, color.a)
	end
end

local function DrawTicks(cx, cy, radius, scale, alpha)
	for index = 0, 47 do
		local angle = math.rad(index * 7.5 - 90)
		local major = index % 4 == 0
		local inner = radius - (major and 12 or 6) * scale
		local outer = radius + (major and 4 or 1) * scale
		local color = major and Color(146, 25, 45, alpha * 0.72) or Color(91, 25, 36, alpha * 0.46)
		surface.SetDrawColor(color)
		surface.DrawLine(cx + math.cos(angle) * inner, cy + math.sin(angle) * inner,
			cx + math.cos(angle) * outer, cy + math.sin(angle) * outer)
	end
end

local function GetVampireCharacter()
	local client = LocalPlayer()
	local character = IsValid(client) and client:GetCharacter()
	if (!character or !character.IsVampire or !character:IsVampire()) then return nil end
	return character
end

local PANEL = {}

function PANEL:Init()
	self:SetSize(ScrW(), ScrH())
	self:SetPos(0, 0)
	self:SetMouseInputEnabled(true)
	self:SetKeyboardInputEnabled(false)
	self.disciplines = {}
	self.activeDiscipline = nil
	self.hoveredPower = nil
	self.openedAt = RealTime()
	self.alpha = 0
end

function PANEL:Refresh(character)
	self.character = character
	self.disciplines = ix.disciplines.GetAccessibleInterfaceDisciplines(character)
	if (#self.disciplines == 1) then self.activeDiscipline = self.disciplines[1] end
end

function PANEL:GetGeometry()
	local scale = math.Clamp(math.min(self:GetWide() / 920, self:GetTall() / 780), 0.68, 1.08)
	return self:GetWide() * 0.5, self:GetTall() * 0.5, scale
end

function PANEL:GetHoveredSegment(radiusMinimum, radiusMaximum, count)
	if (count <= 0) then return nil end
	local mouseX, mouseY = self:LocalCursorPos()
	local centerX, centerY, scale = self:GetGeometry()
	local dx, dy = mouseX - centerX, mouseY - centerY
	local radius = math.sqrt(dx * dx + dy * dy) / scale
	if (radius < radiusMinimum or radius > radiusMaximum) then return nil end
	local angle = math.deg(math.atan2(dy, dx)) + 90
	if (angle < 0) then angle = angle + 360 end
	return math.floor(angle / (360 / count)) + 1
end

function PANEL:Think()
	if (!GetVampireCharacter()) then return ix.disciplines.ClosePowerWheel(false) end
	if (!input.IsKeyDown(KEY_G)) then return ix.disciplines.ClosePowerWheel(true) end
	local outerIndex = self:GetHoveredSegment(220, 304, #self.disciplines)
	if (outerIndex and self.disciplines[outerIndex]) then
		self.activeDiscipline = self.disciplines[outerIndex]
		self.hoveredPower = nil
	end
	if (self.activeDiscipline) then
		local powers = ix.disciplines.GetAvailablePowers(self.character, self.activeDiscipline.id)
		local powerIndex = self:GetHoveredSegment(72, 174, #powers)
		self.hoveredPower = powerIndex and powers[powerIndex] or nil
	end
	self.alpha = Lerp(math.min(FrameTime() * 10, 1), self.alpha, 255)
end

function PANEL:Paint(width, height)
	local cx, cy, scale = self:GetGeometry()
	local alpha = self.alpha
	Derma_DrawBackgroundBlur(self, self.openedAt)

	-- Quiet vignette: near-black glass instead of the old opaque red disks.
	surface.SetDrawColor(2, 1, 3, alpha * 0.82)
	surface.DrawRect(0, 0, width, height)
	for index = 5, 1, -1 do
		local radius = 365 * scale + index * 36 * scale
		draw.NoTexture()
		surface.SetDrawColor(18, 2, 7, alpha * (0.018 * index))
		surface.DrawCircle(cx, cy, radius, 18, 2, 7, alpha * (0.018 * index))
	end

	local backdrop = 680 * scale
	surface.SetMaterial(wheelBackground)
	surface.SetDrawColor(165, 80, 90, alpha * 0.36)
	surface.DrawTexturedRect(cx - backdrop * 0.5, cy - backdrop * 0.5, backdrop, backdrop)

	DrawRing(cx, cy, 316 * scale, Color(111, 12, 31, alpha * 0.72), 2)
	DrawRing(cx, cy, 308 * scale, Color(42, 31, 35, alpha * 0.95), 1)
	DrawRing(cx, cy, 211 * scale, Color(75, 13, 27, alpha * 0.58), 2)
	DrawTicks(cx, cy, 310 * scale, scale, alpha)

	-- Header with restrained engraved ornaments.
	draw.SimpleText("ВАМПИРСКИЕ ДИСЦИПЛИНЫ", "AfterlightWheelTitle", cx + 2, cy - 344 * scale + 2,
		Color(10, 2, 4, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText("ВАМПИРСКИЕ ДИСЦИПЛИНЫ", "AfterlightWheelTitle", cx, cy - 344 * scale,
		Color(194, 47, 67, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	surface.SetDrawColor(116, 20, 37, alpha * 0.7)
	surface.DrawLine(cx - 190 * scale, cy - 323 * scale, cx - 48 * scale, cy - 323 * scale)
	surface.DrawLine(cx + 48 * scale, cy - 323 * scale, cx + 190 * scale, cy - 323 * scale)

	local count = #self.disciplines
	if (count <= 0) then
		draw.SimpleText("ПЕЧАТИ НЕ НАЙДЕНЫ", "AfterlightWheelDiscipline", cx, cy,
			Color(166, 151, 148, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		return
	end

	local hoveredOuter = self:GetHoveredSegment(220, 304, count)
	local segmentSize = 360 / count
	for index, discipline in ipairs(self.disciplines) do
		local gap = math.min(2.4, segmentSize * 0.035)
		local startAngle = -90 + (index - 1) * segmentSize + gap
		local endAngle = -90 + index * segmentSize - gap
		local selected = self.activeDiscipline and self.activeDiscipline.id == discipline.id
		local hovered = hoveredOuter == index
		local hot = hovered or selected

		DrawWedge(cx, cy, 220 * scale, 300 * scale, startAngle, endAngle,
			hot and Color(35, 7, 14, alpha * 0.94) or Color(8, 7, 10, alpha * 0.86))
		DrawWedge(cx, cy, 220 * scale, 224 * scale, startAngle, endAngle,
			hot and Color(181, 32, 53, alpha) or Color(65, 16, 28, alpha * 0.82))
		DrawWedge(cx, cy, 296 * scale, 300 * scale, startAngle, endAngle,
			hot and Color(126, 25, 42, alpha) or Color(52, 23, 31, alpha * 0.76))

		local middle = math.rad((startAngle + endAngle) * 0.5)
		local iconX, iconY = cx + math.cos(middle) * 259 * scale, cy + math.sin(middle) * 259 * scale
		local icon = discipline.definition and GetIcon(discipline.definition.icon)
		local seal = (hot and 54 or 48) * scale
		draw.NoTexture()
		surface.SetDrawColor(5, 4, 7, alpha * 0.98)
		surface.DrawCircle(iconX, iconY - 8 * scale, seal * 0.66, 5, 4, 7, alpha * 0.98)
		DrawRing(iconX, iconY - 8 * scale, seal * 0.66, hot and Color(180, 39, 58, alpha) or Color(94, 68, 72, alpha), 2)
		DrawIcon(icon, iconX, iconY - 8 * scale, seal, hot and Color(255, 238, 226, alpha) or Color(192, 181, 176, alpha))

		local name = discipline.definition and discipline.definition.name or discipline.id
		draw.SimpleText(name, "AfterlightWheelDiscipline", iconX, iconY + 31 * scale,
			Color(229, 216, 206, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText("УРОВЕНЬ " .. tostring(discipline.level), "AfterlightWheelRoman", iconX, iconY + 49 * scale,
			Color(140, 73, 82, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	local powers = self.activeDiscipline and ix.disciplines.GetAvailablePowers(self.character, self.activeDiscipline.id) or {}
	if (#powers > 0) then
		local hoveredPower = self:GetHoveredSegment(72, 174, #powers)
		local segment = 360 / #powers
		for index, power in ipairs(powers) do
			local gap = math.min(3.2, segment * 0.05)
			local startAngle = -90 + (index - 1) * segment + gap
			local endAngle = -90 + index * segment - gap
			local hot = hoveredPower == index
			DrawWedge(cx, cy, 72 * scale, 174 * scale, startAngle, endAngle,
				hot and Color(52, 8, 18, alpha * 0.96) or Color(9, 7, 11, alpha * 0.94))
			DrawWedge(cx, cy, 168 * scale, 174 * scale, startAngle, endAngle,
				hot and Color(216, 42, 62, alpha) or Color(84, 19, 33, alpha * 0.84))
			DrawWedge(cx, cy, 72 * scale, 75 * scale, startAngle, endAngle,
				hot and Color(139, 26, 45, alpha) or Color(52, 18, 27, alpha * 0.75))

			local middle = math.rad((startAngle + endAngle) * 0.5)
			local labelX = cx + math.cos(middle) * 122 * scale
			local labelY = cy + math.sin(middle) * 122 * scale
			local powerIcon = GetIcon(power.icon)
			if (powerIcon) then DrawIcon(powerIcon, labelX, labelY - 15 * scale, 34 * scale, Color(224, 209, 201, alpha)) end
			local textY = labelY + (powerIcon and 13 or 0) * scale
			draw.SimpleText(power.name, "AfterlightWheelPower", labelX, textY,
				hot and Color(255, 234, 220, alpha) or Color(205, 194, 188, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			local cooldown = ix.disciplines.GetClientCooldown and ix.disciplines.GetClientCooldown(power.disciplineID, power.id) or 0
			if (cooldown > 0) then
				draw.SimpleText("ОТКАТ  " .. math.ceil(cooldown) .. " с", "AfterlightWheelSmall", labelX, textY + 19 * scale,
					Color(211, 49, 63, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
	elseif (self.activeDiscipline) then
		draw.SimpleText("СИЛЫ НЕ ЗАРЕГИСТРИРОВАНЫ", "AfterlightWheelSmall", cx, cy + 130 * scale,
			Color(148, 112, 116, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	-- Central reliquary anchors the composition without a large flat disk.
	draw.NoTexture()
	surface.SetDrawColor(3, 3, 5, alpha * 0.98)
	surface.DrawCircle(cx, cy, 61 * scale, 3, 3, 5, alpha * 0.98)
	DrawRing(cx, cy, 61 * scale, Color(112, 19, 35, alpha), 2)
	DrawRing(cx, cy, 55 * scale, Color(63, 54, 57, alpha * 0.82), 1)
	local activeIcon = self.activeDiscipline and self.activeDiscipline.definition and GetIcon(self.activeDiscipline.definition.icon)
	if (activeIcon) then DrawIcon(activeIcon, cx, cy - 8 * scale, 62 * scale, Color(236, 220, 210, alpha)) end
	local centerText = self.hoveredPower and self.hoveredPower.name or
		(self.activeDiscipline and self.activeDiscipline.definition.name or "ВЫБЕРИТЕ ПЕЧАТЬ")
	draw.SimpleText(centerText, "AfterlightWheelSmall", cx, cy + 45 * scale,
		Color(201, 185, 179, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

	draw.SimpleText("ОТПУСТИТЕ G, ЧТОБЫ СВЯЗАТЬ СИЛУ", "AfterlightWheelSmall", cx, cy + 347 * scale,
		Color(120, 78, 84, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

vgui.Register("AfterlightDisciplineWheel", PANEL, "EditablePanel")

function ix.disciplines.OpenPowerWheel()
	if (IsValid(ix.gui.afterlightDisciplineWheel)) then return end
	local character = GetVampireCharacter()
	if (!character or #ix.disciplines.GetAccessibleInterfaceDisciplines(character) == 0) then return end
	local panel = vgui.Create("AfterlightDisciplineWheel")
	panel:Refresh(character)
	ix.gui.afterlightDisciplineWheel = panel
	gui.EnableScreenClicker(true)
	input.SetCursorPos(ScrW() * 0.5, ScrH() * 0.5)
end

function ix.disciplines.ClosePowerWheel(confirm)
	local panel = ix.gui.afterlightDisciplineWheel
	if (!IsValid(panel)) then return end
	if (confirm and panel.hoveredPower and panel.activeDiscipline) then
		net.Start("AfterlightDisciplineSelect")
			net.WriteString(panel.activeDiscipline.id)
			net.WriteString(panel.hoveredPower.id)
		net.SendToServer()
	end
	panel:Remove()
	ix.gui.afterlightDisciplineWheel = nil
	gui.EnableScreenClicker(false)
end

local wasGDown, wasMiddleDown = false, false
hook.Add("Think", "AfterlightDisciplineInput", function()
	local character = GetVampireCharacter()
	local hasDisciplines = character and #ix.disciplines.GetAccessibleInterfaceDisciplines(character) > 0
	local keyboardFocus = vgui.GetKeyboardFocus()
	local blocked = gui.IsGameUIVisible() or IsValid(keyboardFocus) or IsValid(ix.gui.menu) or IsValid(ix.gui.characterMenu)
	local gDown = input.IsKeyDown(KEY_G)
	if (gDown and !wasGDown and hasDisciplines and !blocked) then ix.disciplines.OpenPowerWheel() end
	if (!gDown and wasGDown and IsValid(ix.gui.afterlightDisciplineWheel)) then ix.disciplines.ClosePowerWheel(true) end
	wasGDown = gDown

	local middleDown = input.IsMouseDown(MOUSE_MIDDLE)
	local selectedPower = character and ix.disciplines.GetSelectedPower(character)
	if (middleDown and !wasMiddleDown and hasDisciplines and selectedPower and !blocked and !IsValid(ix.gui.afterlightDisciplineWheel)) then
		net.Start("AfterlightDisciplineUse")
		net.SendToServer()
	end
	wasMiddleDown = middleDown
end)

hook.Add("PlayerBindPress", "AfterlightDisciplineInputBinds", function(client, bind, pressed)
	if (!pressed or client != LocalPlayer()) then return end
	bind = string.lower(bind)
	local character = GetVampireCharacter()
	if (character and #ix.disciplines.GetAccessibleInterfaceDisciplines(character) > 0 and bind == "impulse 201") then return true end
	if (character and ix.disciplines.GetSelectedPower(character) and string.find(bind, "+attack3", 1, true)) then return true end
end)
