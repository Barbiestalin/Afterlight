if (!CLIENT) then return end

local GROUP_ORDER = {
	attributes = {"physical", "social", "mental"},
	abilities = {"talents", "skills", "knowledges"},
	virtues = {"virtues"}
}

local ROW = {}
function ROW:Init()
	self.value = 0
	self.baseValue = 0
	self.dots = {}
	self.label = self:Add("DLabel")
	self.label:SetFont("ixSmallFont")
	self.label:SetTextColor(Color(225, 220, 212))

	for i = 1, ix.vtm.stats.MAX_VALUE do
		local dot = self:Add("DButton")
		dot:SetText("")
		dot.index = i
		dot.DoClick = function(button)
			if (IsValid(self.sheet)) then self.sheet:RequestValue(self.definition.id, button.index) end
		end
		dot.Paint = function(button, w, h)
			local active = button.index <= self.value
			local temporary = active and button.afterlightTemporary == true
			local color = temporary and Color(35, 115, 220) or
				(active and Color(142, 8, 28) or Color(20, 18, 19))
			if (button:IsHovered()) then
				color = temporary and Color(70, 155, 255) or
					(active and Color(190, 18, 43) or Color(80, 68, 68))
			end
			draw.NoTexture()
			surface.SetDrawColor(color)
			surface.DrawCircle(w * 0.5, h * 0.5, math.min(w, h) * 0.30,
				color.r, color.g, color.b, 255)
			surface.SetDrawColor(210, 198, 185, 190)
			surface.DrawOutlinedRect(2, 2, w - 4, h - 4, 1)
		end
		self.dots[i] = dot
	end
end

function ROW:SetDefinition(definition, sheet)
	self.definition = definition
	self.sheet = sheet
	self.label:SetText(definition.name)
	self.label:SizeToContents()
end

function ROW:SetValue(value, temporaryBonus)
	self.baseValue = math.Clamp(math.floor(tonumber(value) or 0), 0, ix.vtm.stats.MAX_VALUE)
	local bonus = math.max(math.floor(tonumber(temporaryBonus) or 0), 0)
	self.value = math.min(self.baseValue + bonus, ix.vtm.stats.MAX_VALUE)
	for _, dot in ipairs(self.dots or {}) do
		dot.afterlightTemporary = bonus > 0 and dot.index > self.baseValue and dot.index <= self.value
	end
end

function ROW:PerformLayout(w, h)
	local dotsWidth = math.min(105, w * 0.42)
	self.label:SetPos(4, 0)
	self.label:SetSize(math.max(w - dotsWidth - 8, 20), h)
	local dotSize = math.min(18, h - 2)
	local gap = math.max((dotsWidth - dotSize * ix.vtm.stats.MAX_VALUE) / math.max(ix.vtm.stats.MAX_VALUE - 1, 1), 1)
	local x = w - dotsWidth
	for _, dot in ipairs(self.dots) do
		dot:SetPos(x, (h - dotSize) * 0.5)
		dot:SetSize(dotSize, dotSize)
		x = x + dotSize + gap
	end
end
vgui.Register("AfterlightVTMStatRow", ROW, "DPanel")

local DISCIPLINE_ROW = {}
function DISCIPLINE_ROW:Init()
	self.level = 0
	self.label = self:Add("DLabel")
	self.label:SetFont("ixSmallFont")
	self.label:SetTextColor(Color(225, 220, 212))
	self.dots = {}

	for index = 1, ix.disciplines.MAX_LEVEL do
		local dot = self:Add("DButton")
		dot:SetText("")
		dot.index = index
		dot.DoClick = function(button)
			if (IsValid(self.sheet)) then
				self.sheet:RequestDisciplineValue(self.definition.id, button.index)
			end
		end
		dot.Paint = function(panel, w, h)
			local active = panel.index <= self.level
			local color = active and Color(142, 8, 28) or Color(20, 18, 19)
			draw.NoTexture()
			surface.SetDrawColor(color)
			surface.DrawCircle(w * 0.5, h * 0.5, math.min(w, h) * 0.30,
				color.r, color.g, color.b, 255)
			surface.SetDrawColor(210, 198, 185, 190)
			surface.DrawOutlinedRect(2, 2, w - 4, h - 4, 1)
		end
		self.dots[index] = dot
	end
end

function DISCIPLINE_ROW:SetDiscipline(definition, level)
	self.definition = definition
	self.level = math.Clamp(math.floor(tonumber(level) or 0), 0, definition.maxLevel)
	self.label:SetText(definition.name)
end

function DISCIPLINE_ROW:PerformLayout(w, h)
	local dotsWidth = math.min(105, w * 0.42)
	self.label:SetPos(4, 0)
	self.label:SetSize(math.max(w - dotsWidth - 8, 20), h)
	local dotSize = math.min(18, h - 2)
	local gap = math.max((dotsWidth - dotSize * ix.disciplines.MAX_LEVEL) /
		math.max(ix.disciplines.MAX_LEVEL - 1, 1), 1)
	local x = w - dotsWidth
	for _, dot in ipairs(self.dots) do
		dot:SetPos(x, (h - dotSize) * 0.5)
		dot:SetSize(dotSize, dotSize)
		x = x + dotSize + gap
	end
end
vgui.Register("AfterlightVTMDisciplineRow", DISCIPLINE_ROW, "DPanel")

local SHEET = {}
function SHEET:Init()
	self.mode = "view"
	self.data = ix.vtm.stats.Normalize({})
	self.sections = {}
	self.rows = {}
	self.temporaryBonuses = {}

	for _, category in ipairs(ix.vtm.stats.CATEGORIES) do
		local section = self:Add("DPanel")
		section.category = category
		section.Paint = function(panel, w, h)
			surface.SetDrawColor(4, 4, 5, 215)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(120, 7, 24, 230)
			surface.DrawRect(0, 0, w, 30)
			surface.SetDrawColor(175, 24, 43, 180)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
		end

		section.title = section:Add("DLabel")
		section.title:SetFont("ixMediumFont")
		local categoryTitles = {
			attributes = "ХАРАКТЕРИСТИКИ",
			abilities = "СПОСОБНОСТИ",
			virtues = "ДОБРОДЕТЕЛИ"
		}
		section.title:SetText(categoryTitles[category])
		section.title:SetTextColor(color_white)
		section.points = section:Add("DLabel")
		section.points:SetFont("ixSmallFont")
		section.points:SetTextColor(Color(240, 220, 185))
		section.points:SetContentAlignment(6)
		section.columns = {}

		for _, group in ipairs(GROUP_ORDER[category]) do
			local column = section:Add("DPanel")
			column.group = group
			column.Paint = nil
			column.title = column:Add("DLabel")
			column.title:SetFont("ixSmallFont")
			column.title:SetText(string.upper(ix.vtm.stats.groupNames[group]))
			column.title:SetTextColor(Color(206, 197, 186))
			column.title:SetContentAlignment(5)
			column.rows = {}

			for _, id in ipairs(ix.vtm.stats.groups[category][group]) do
				local row = column:Add("AfterlightVTMStatRow")
				row:SetDefinition(ix.vtm.stats.list[id], self)
				column.rows[#column.rows + 1] = row
				self.rows[id] = row
			end
			section.columns[#section.columns + 1] = column
		end
		self.sections[category] = section
	end

	self.disciplineData = {}
	self.disciplineRows = {}
	self.disciplineSection = self:Add("DPanel")
	self.disciplineSection:SetVisible(false)
	self.disciplineSection.Paint = function(panel, w, h)
		surface.SetDrawColor(4, 4, 5, 215)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(120, 7, 24, 230)
		surface.DrawRect(0, 0, w, 30)
		surface.SetDrawColor(175, 24, 43, 180)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	self.disciplineSection.title = self.disciplineSection:Add("DLabel")
	self.disciplineSection.title:SetFont("ixMediumFont")
	self.disciplineSection.title:SetText("ДИСЦИПЛИНЫ")
	self.disciplineSection.title:SetTextColor(color_white)
	self.disciplineSection.points = self.disciplineSection:Add("DLabel")
	self.disciplineSection.points:SetFont("ixSmallFont")
	self.disciplineSection.points:SetTextColor(Color(240, 220, 185))
	self.disciplineSection.points:SetContentAlignment(6)

	self.confirm = self:Add("DButton")
	self.confirm:SetFont("ixMediumFont")
	self.confirm:SetText("ПОДТВЕРДИТЬ")
	self.confirm:SetTextColor(color_white)
	self.confirm.Paint = function(button, w, h)
		local disabled = button.locked or !button:IsEnabled()
		local target = disabled and Color(48, 48, 48, 230) or
			(button.Depressed and Color(185, 18, 45, 250) or
				(button:IsHovered() and Color(155, 12, 35, 245) or Color(105, 7, 25, 235)))
		button.smoothColor = button.smoothColor or Color(target.r, target.g, target.b, target.a)
		local speed = math.min(FrameTime() * 12, 1)
		button.smoothColor.r = Lerp(speed, button.smoothColor.r, target.r)
		button.smoothColor.g = Lerp(speed, button.smoothColor.g, target.g)
		button.smoothColor.b = Lerp(speed, button.smoothColor.b, target.b)
		button.smoothColor.a = Lerp(speed, button.smoothColor.a, target.a)
		surface.SetDrawColor(button.smoothColor)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(205, 55, 70, 210)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	self.confirm.DoClick = function() self:ConfirmSelection() end
end

function SHEET:SetMode(mode)
	self.mode = mode or "view"
	if (IsValid(self.confirm)) then self.confirm:SetVisible(self.mode != "view") end
	self:InvalidateLayout(true)
end

function SHEET:SetChangeCallback(callback)
	self.changeCallback = callback
end

function SHEET:HasUnspentPoints()
	for _, category in ipairs(ix.vtm.stats.POINT_CATEGORIES) do
		if ((self.data.unspent[category] or 0) > 0) then return true end
	end
	return false
end

function SHEET:CanConfirmSelection()
	return self.mode != "view" and !self.locked and !self.awaitingCommit and !self:HasUnspentPoints()
end

function SHEET:SetStatsData(data, preserveDraft)
	self.data = ix.vtm.stats.Normalize(data)
	if (self.mode == "spend" and !preserveDraft) then
		self.committed = table.Copy(self.data)
		self.awaitingCommit = false
		-- A successful server response with no remaining points settles into a
		-- stable confirmed state instead of flashing back to an active button.
		self.locked = !self:HasUnspentPoints()
	end
	if (self.mode == "creation") then self.locked = self.data.creationConfirmed == true end

	for _, id in ipairs(ix.vtm.stats.order) do
		if (IsValid(self.rows[id])) then self.rows[id]:SetValue(self.data.values[id], self.temporaryBonuses[id]) end
	end
	for category, section in pairs(self.sections) do
		section.points:SetText("Свободно: " .. tostring(self.data.unspent[category] or 0))
	end
	self.disciplineSection.points:SetText("Свободно: " .. tostring(self.data.unspent.disciplines or 0))
	if (IsValid(self.confirm)) then
		self.confirm.locked = self.locked or self.awaitingCommit
		self.confirm:SetEnabled(self:CanConfirmSelection())
		self.confirm:SetText(self.locked and "ПОДТВЕРЖДЕНО" or
			(self.awaitingCommit and "СОХРАНЕНИЕ..." or
				(self:HasUnspentPoints() and "РАСПРЕДЕЛИТЕ ВСЕ ОЧКИ" or "ПОДТВЕРДИТЬ")))
	end
end

function SHEET:SetTemporaryBonuses(bonuses)
	self.temporaryBonuses = istable(bonuses) and table.Copy(bonuses) or {}
	for _, id in ipairs(ix.vtm.stats.order) do
		if (IsValid(self.rows[id])) then
			self.rows[id]:SetValue(self.data.values[id], self.temporaryBonuses[id])
		end
	end
end

function SHEET:SetDisciplineData(data, preserveDraft)
	self.disciplineData = ix.disciplines.Normalize(data)
	if (self.mode == "spend" and !preserveDraft) then
		self.committedDisciplines = table.Copy(self.disciplineData)
	end
	local learned = {}
	for _, id in ipairs(ix.disciplines.order) do
		if (self.disciplineData[id]) then learned[#learned + 1] = id end
	end

	for id, row in pairs(self.disciplineRows) do
		if (!self.disciplineData[id]) then
			if (IsValid(row)) then row:Remove() end
			self.disciplineRows[id] = nil
		end
	end

	for _, id in ipairs(learned) do
		local row = self.disciplineRows[id]
		if (!IsValid(row)) then
			row = self.disciplineSection:Add("AfterlightVTMDisciplineRow")
			row.sheet = self
			self.disciplineRows[id] = row
		end
		row:SetDiscipline(ix.disciplines.list[id], self.disciplineData[id].level)
	end

	self.learnedDisciplines = learned
	self.disciplineSection:SetVisible(#learned > 0)
	self:InvalidateLayout(true)
end

function SHEET:RequestDisciplineValue(id, requested)
	if (self.locked or self.awaitingCommit or self.mode != "spend") then return end
	local definition = ix.disciplines.Get(id)
	local entry = self.disciplineData[id]
	if (!definition or !entry) then return end
	local committed = self.committedDisciplines and self.committedDisciplines[id]
	local minimum = committed and committed.level or entry.level
	local current = entry.level
	requested = math.Clamp(math.floor(tonumber(requested) or current), minimum, definition.maxLevel)
	if (requested == current) then requested = math.max(current - 1, minimum) end
	local difference = requested - current
	if (difference > (self.data.unspent.disciplines or 0)) then return end
	entry.level = requested
	self.data.unspent.disciplines = self.data.unspent.disciplines - difference
	self:SetDisciplineData(self.disciplineData, true)
	self:SetStatsData(self.data, true)
end

function SHEET:RequestValue(id, requested)
	if (self.locked or self.awaitingCommit or self.mode == "view") then return end
	local definition = ix.vtm.stats.GetDefinition(id)
	if (!definition) then return end
	if (definition.vampireOnly and !self.allowVampireOnly) then return end
	local current = self.data.values[id]
	local minimum = definition.base
	if (self.mode == "spend" and self.committed) then minimum = self.committed.values[id] end

	requested = math.Clamp(math.floor(requested), minimum, definition.max)
	if (requested == current) then requested = math.max(current - 1, minimum) end
	local difference = requested - current
	if (difference > (self.data.unspent[definition.category] or 0)) then return end
	self.data.values[id] = requested
	self.data.unspent[definition.category] = self.data.unspent[definition.category] - difference
	self:SetStatsData(self.data, true)
	if (self.mode == "creation" and self.changeCallback) then
		self.changeCallback(table.Copy(self.data), false)
	end
end

function SHEET:ConfirmSelection()
	if (!self:CanConfirmSelection()) then return end
	if (self.mode == "creation") then
		self.data.creationConfirmed = true
		self.locked = true
		self:SetStatsData(self.data, true)
		if (self.changeCallback) then self.changeCallback(table.Copy(self.data), true) end
	elseif (self.mode == "spend") then
		self.awaitingCommit = true
		self:SetStatsData(self.data, true)
		local disciplineLevels = {}
		for id, entry in pairs(self.disciplineData) do disciplineLevels[id] = entry.level end
		if (self.changeCallback) then
			self.changeCallback(table.Copy(self.data.values), disciplineLevels, true)
		end
	end
end

function SHEET:PerformLayout(w, h)
	local y = 0
	for _, category in ipairs(ix.vtm.stats.CATEGORIES) do
		local section = self.sections[category]
		local rowCount = category == "abilities" and 10 or 3
		local sectionHeight = 58 + rowCount * 24
		section:SetPos(0, y)
		section:SetSize(w, sectionHeight)
		section.title:SetPos(10, 2)
		section.title:SetSize(w * 0.55, 27)
		section.points:SetPos(w * 0.55, 2)
		section.points:SetSize(w * 0.43 - 8, 27)

		local columnCount = #section.columns
		local columnWidth = columnCount == 1 and math.min(w * 0.56, 430) or w / 3
		local startX = columnCount == 1 and (w - columnWidth) * 0.5 or 0
		for index, column in ipairs(section.columns) do
			column:SetPos(startX + (index - 1) * columnWidth + 4, 34)
			column:SetSize(columnWidth - 8, sectionHeight - 38)
			local titleHeight = column.group == "virtues" and 0 or 20
			column.title:SetVisible(titleHeight > 0)
			column.title:SetPos(0, 0)
			column.title:SetSize(column:GetWide(), titleHeight)
			for rowIndex, row in ipairs(column.rows) do
				row:SetPos(0, titleHeight + (rowIndex - 1) * 24)
				row:SetSize(column:GetWide(), 22)
			end
		end
		y = y + sectionHeight + 10
	end

	local learned = self.learnedDisciplines or {}
	if (#learned > 0) then
		local columnCount = w >= 620 and 2 or 1
		local rowCount = math.ceil(#learned / columnCount)
		local sectionHeight = 40 + rowCount * 24
		self.disciplineSection:SetPos(0, y)
		self.disciplineSection:SetSize(w, sectionHeight)
		self.disciplineSection.title:SetPos(10, 2)
		self.disciplineSection.title:SetSize(w * 0.55, 27)
		self.disciplineSection.points:SetPos(w * 0.55, 2)
		self.disciplineSection.points:SetSize(w * 0.43 - 8, 27)
		local columnWidth = w / columnCount
		for index, id in ipairs(learned) do
			local row = self.disciplineRows[id]
			local column = (index - 1) % columnCount
			local line = math.floor((index - 1) / columnCount)
			row:SetPos(column * columnWidth + 6, 34 + line * 24)
			row:SetSize(columnWidth - 12, 22)
		end
		y = y + sectionHeight + 10
	end

	if (IsValid(self.confirm) and self.mode != "view") then
		self.confirm:SetPos(math.max(w - 250, 0), y)
		self.confirm:SetSize(math.min(250, w), 36)
		y = y + 44
	end
	self:SetTall(y)
end
vgui.Register("AfterlightVTMStatSheet", SHEET, "DPanel")

ix.vtm.stats.openSheets = ix.vtm.stats.openSheets or setmetatable({}, {__mode = "k"})

function ix.vtm.stats.BuildTemporaryBonuses(character)
	local bonuses = {}
	for _, id in ipairs(ix.vtm.stats.order) do
		local bonus = ix.vtm.stats.GetTemporaryBonus(character, id)
		if (bonus > 0) then bonuses[id] = bonus end
	end
	return bonuses
end

function ix.vtm.stats.RefreshTemporaryBonuses(character)
	local bonuses = ix.vtm.stats.BuildTemporaryBonuses(character)
	for sheet, trackedCharacter in pairs(ix.vtm.stats.openSheets) do
		if (IsValid(sheet) and trackedCharacter == character) then sheet:SetTemporaryBonuses(bonuses) end
	end
end

hook.Add("AfterlightVTMTemporaryBonusesChanged", "AfterlightVTMRefreshTemporaryDots", function(character)
	if (character) then ix.vtm.stats.RefreshTemporaryBonuses(character) end
end)

function ix.vtm.stats.RefreshOpenSheets(character, data, disciplineData)
	for sheet, trackedCharacter in pairs(ix.vtm.stats.openSheets) do
		if (IsValid(sheet) and (!character or trackedCharacter == character)) then
			sheet:SetTemporaryBonuses(ix.vtm.stats.BuildTemporaryBonuses(trackedCharacter))
			sheet:SetStatsData(data or ix.vtm.stats.GetData(trackedCharacter))
			local isVampire = trackedCharacter and trackedCharacter.IsVampire and trackedCharacter:IsVampire()
			sheet:SetDisciplineData(isVampire and
				(disciplineData or ix.disciplines.GetCharacterData(trackedCharacter)) or {})
		end
	end
end

local function PatchCharacterInfo()
	local control = vgui.GetControlTable("ixCharacterInfo")
	if (!control or control.afterlightVTMSheet) then return control != nil end
	control.afterlightVTMSheet = true
	local originalUpdate = control.Update

	function control:Update(character)
		originalUpdate(self, character)
		if (!character) then return end

		-- The unified VTM sheet replaces only visual legacy blocks. Existing
		-- attribute and vampireDisciplines data remain untouched for compatibility.
		if (IsValid(self.attributes)) then self.attributes:SetVisible(false) end
		if (IsValid(self.afterlightDisciplinePanel)) then
			self.afterlightDisciplinePanel:Remove()
			self.afterlightDisciplinePanel = nil
		end

		if (!IsValid(self.afterlightVTMPanel)) then
			self.afterlightVTMPanel = self:Add("AfterlightVTMStatSheet")
			self.afterlightVTMPanel:Dock(TOP)
			self.afterlightVTMPanel:DockMargin(0, 0, 0, 8)
			self.afterlightVTMPanel:SetMode("spend")
			self.afterlightVTMPanel:SetChangeCallback(function(values, disciplineLevels)
				net.Start("AfterlightVTMCommit")
					net.WriteTable(values)
					net.WriteTable(disciplineLevels or {})
				net.SendToServer()
			end)
		end

		local isVampire = character.IsVampire and character:IsVampire()
		self.afterlightVTMPanel.allowVampireOnly = isVampire
		ix.vtm.stats.openSheets[self.afterlightVTMPanel] = character
		self.afterlightVTMPanel:SetTemporaryBonuses(ix.vtm.stats.BuildTemporaryBonuses(character))
		self.afterlightVTMPanel:SetStatsData(ix.vtm.stats.GetData(character))
		self.afterlightVTMPanel:SetDisciplineData(isVampire and
			ix.disciplines.GetCharacterData(character) or {})
	end
	return true
end

if (!PatchCharacterInfo()) then
	timer.Create("AfterlightVTMCharacterInfo", 0.1, 100, function()
		if (PatchCharacterInfo()) then timer.Remove("AfterlightVTMCharacterInfo") end
	end)
end

hook.Add("InitPostEntity", "AfterlightVTMCharacterInfo", function()
	-- Intentionally no return: preserve Helix GM:InitPostEntity, HUD bars and options sync.
	PatchCharacterInfo()
end)

function ix.vtm.stats.OpenAdminSheet(characterName, data, overview, disciplineData, target)
	if (IsValid(ix.gui.afterlightVTMAdminSheet)) then ix.gui.afterlightVTMAdminSheet:Remove() end
	local frame = vgui.Create("DFrame")
	frame:SetSize(math.min(ScrW() * 0.72, 1180), math.min(ScrH() * 0.88, 900))
	frame:Center()
	frame:SetTitle("VTM-лист: " .. tostring(characterName))
	frame:MakePopup()

	local scroll = frame:Add("DScrollPanel")
	scroll:Dock(FILL)

	overview = istable(overview) and overview or {}
	local info = scroll:Add("ixCategoryPanel")
	info:SetText("Основные показатели")
	info:Dock(TOP)
	info:DockMargin(0, 0, 0, 8)

	local entries = {
		{"Фракция", overview.faction},
		{"Наличные", overview.money != nil and ix.currency.Get(overview.money) or nil},
		{"Вид", overview.species},
		{"Клан", overview.clan},
		{"Поколение", overview.generation},
		{"Класс", overview.class}
	}
	-- ixCategoryPanel does not provide the list expected by ixListRow:SetList.
	-- Keep a dedicated row list, just like stock ixCharacterInfo does.
	local infoRows = {}
	for _, entry in ipairs(entries) do
		if (entry[2] != nil and tostring(entry[2]) != "") then
			local row = info:Add("ixListRow")
			row:SetList(infoRows)
			row:Dock(TOP)
			row:SetLabelText(entry[1])
			row:SetText(tostring(entry[2]))
			row:SizeToContents()
		end
	end
	info:SizeToContents()

	local admin = scroll:Add("ixCategoryPanel")
	admin:SetText("Администрирование чарлиста")
	admin:Dock(TOP)
	admin:DockMargin(0, 0, 0, 8)
	admin:SetTall(150)

	local amount = admin:Add("DNumberWang")
	amount:SetMinMax(1, 100)
	amount:SetDecimals(0)
	amount:SetValue(1)
	amount:SetPos(10, 38)
	amount:SetSize(70, 26)

	local categories = {
		{"Характеристики", "attributes"},
		{"Способности", "abilities"},
		{"Добродетели", "virtues"},
		{"Дисциплины", "disciplines"}
	}
	for index, category in ipairs(categories) do
		local categoryTitle, categoryID = category[1], category[2]
		local button = admin:Add("DButton")
		button:SetText("Добавить: " .. categoryTitle)
		if (categoryID == "disciplines") then button:SetEnabled(overview.species == "Вампир") end
		button:SetPos(90 + (index - 1) * 155, 38)
		button:SetSize(145, 26)
		button.DoClick = function()
			if (!IsValid(target)) then return end
			net.Start("AfterlightVTMAdminAction")
				net.WriteString("add")
				net.WriteEntity(target)
				net.WriteString(categoryID)
				net.WriteUInt(math.Clamp(math.floor(tonumber(amount:GetValue()) or 1), 1, 100), 8)
			net.SendToServer()
		end
	end

	local reset = admin:Add("DButton")
	reset:SetText("ОЧИСТИТЬ ЧАР. ЛИСТ И ВЕРНУТЬ СТАРТОВЫЕ ОЧКИ")
	reset:SetPos(90, 72)
	reset:SetSize(605, 28)
	reset.DoClick = function()
		if (!IsValid(target)) then return end
		Derma_Query(
			"Все значения будут сброшены до базовых, а стартовые очки возвращены в свободные резервы.",
			"Подтверждение очистки",
			"Очистить", function()
				net.Start("AfterlightVTMAdminAction")
					net.WriteString("reset")
					net.WriteEntity(target)
				net.SendToServer()
			end,
			"Отмена"
		)
	end

	local discipline = admin:Add("DComboBox")
	discipline:SetPos(10, 110)
	discipline:SetSize(280, 26)
	discipline:SetValue("Выберите дисциплину")
	for _, id in ipairs(ix.disciplines.order) do
		discipline:AddChoice(ix.disciplines.list[id].name, id)
	end
	local selectedDiscipline
	discipline.OnSelect = function(_, _, _, id) selectedDiscipline = id end

	local grantDiscipline = admin:Add("DButton")
	grantDiscipline:SetPos(300, 110)
	grantDiscipline:SetSize(135, 26)
	grantDiscipline:SetText("Добавить (0)")
	grantDiscipline:SetEnabled(overview.species == "Вампир")
	grantDiscipline.DoClick = function()
		if (!IsValid(target) or !selectedDiscipline) then return end
		net.Start("AfterlightVTMAdminAction")
			net.WriteString("discipline_grant")
			net.WriteEntity(target)
			net.WriteString(selectedDiscipline)
		net.SendToServer()
	end

	local removeDiscipline = admin:Add("DButton")
	removeDiscipline:SetPos(445, 110)
	removeDiscipline:SetSize(135, 26)
	removeDiscipline:SetText("Удалить выбранную")
	removeDiscipline:SetEnabled(overview.species == "Вампир")
	removeDiscipline.DoClick = function()
		if (!IsValid(target) or !selectedDiscipline) then return end
		Derma_Query(
			"Выбранная дисциплина и вложенные в неё уровни будут удалены.",
			"Подтверждение удаления дисциплины",
			"Удалить", function()
				net.Start("AfterlightVTMAdminAction")
					net.WriteString("discipline_remove")
					net.WriteEntity(target)
					net.WriteString(selectedDiscipline)
				net.SendToServer()
			end,
			"Отмена"
		)
	end

	local clearDisciplines = admin:Add("DButton")
	clearDisciplines:SetPos(590, 110)
	clearDisciplines:SetSize(148, 26)
	clearDisciplines:SetText("Очистить дисциплины")
	clearDisciplines:SetEnabled(overview.species == "Вампир")
	clearDisciplines.DoClick = function()
		if (!IsValid(target)) then return end
		Derma_Query(
			"Все дисциплины персонажа будут удалены. Обычные характеристики не изменятся.",
			"Подтверждение очистки дисциплин",
			"Очистить", function()
				net.Start("AfterlightVTMAdminAction")
					net.WriteString("discipline_clear")
					net.WriteEntity(target)
				net.SendToServer()
			end,
			"Отмена"
		)
	end

	local sheet = scroll:Add("AfterlightVTMStatSheet")
	sheet:Dock(TOP)
	sheet:SetMode("view")
	sheet:SetStatsData(data)
	sheet:SetDisciplineData(disciplineData)
	ix.gui.afterlightVTMAdminSheet = frame
end

hook.Add("PopulateScoreboardPlayerMenu", "AfterlightVTMAdminSheet", function(target, menu)
	if (!LocalPlayer():IsAdmin()) then return end
	menu:AddOption("Открыть VTM-лист", function()
		net.Start("AfterlightVTMAdminRequest")
			net.WriteEntity(target)
		net.SendToServer()
	end)
end)
