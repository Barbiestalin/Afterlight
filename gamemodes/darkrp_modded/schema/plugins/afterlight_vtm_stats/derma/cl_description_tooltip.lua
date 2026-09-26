if (!CLIENT) then return end

-- Таблица создаётся и в libs/cl_descriptions.lua; здесь страховка от любого
-- порядка включения файлов плагина.
ix.vtm = ix.vtm or {}
ix.vtm.descriptions = ix.vtm.descriptions or {}

-- Высота текста с переносом по словам на maxWide, замеренная через surface.
-- Не зависит от отложенных layout-пассов VGUI (SizeToContentsY/GetContentSize
-- в момент создания лейбла возвращали неверную высоту — тултип улетал вверх
-- экрана): размер известен ДО первой отрисовки и совпадает с отрисовкой.
local function WrappedHeight(text, font, maxWide)
	surface.SetFont(font)
	local _, lineH = surface.GetTextSize("Wy")
	local spaceW = surface.GetTextSize(" ")
	local lines, curW = 1, 0
	for word in string.gmatch(text, "%S+") do
		local wordW = surface.GetTextSize(word)
		local add = (curW == 0) and wordW or spaceW + wordW
		if (curW > 0 and curW + add > maxWide) then
			lines = lines + 1
			curW = wordW
		else
			curW = curW + add
		end
	end
	return lines * (lineH + 2)
end

-- Тултип уровня: правый клик по точке статистики или дисциплины.
-- Панель не перехватывает мышь: любой следующий клик за её пределами
-- (или новый правый клик) закрывает её, закрытие листа закрывает и тултип.
local PANEL = {}

function PANEL:Init()
	self:SetMouseInputEnabled(false)
	self:SetKeyboardInputEnabled(false)
	self:SetZPos(999)
	self.armTime = SysTime() + 0.25
	self.prevLeft = input.IsMouseDown(MOUSE_LEFT)
	self.prevRight = input.IsMouseDown(MOUSE_RIGHT)

	self.title = self:Add("DLabel")
	self.title:SetFont("ixSmallBoldFont")
	self.title:SetTextColor(Color(240, 220, 185))
	self.title:SetWrap(true)

	self.body = self:Add("DLabel")
	self.body:SetFont("ixSmallFont")
	self.body:SetTextColor(Color(225, 220, 212))
	self.body:SetWrap(true)
end

function PANEL:SetContent(titleText, bodyText, width)
	width = width or 340
	local inner = width - 20
	self:SetWide(width)

	self.titleH = WrappedHeight(titleText, "ixSmallBoldFont", inner)
	self.bodyH = WrappedHeight(bodyText, "ixSmallFont", inner)

	self.title:SetPos(10, 8)
	self.title:SetWide(inner)
	self.title:SetTall(self.titleH)
	self.title:SetText(titleText)

	self.body:SetPos(10, 8 + self.titleH + 6)
	self.body:SetWide(inner)
	self.body:SetTall(self.bodyH)
	self.body:SetText(bodyText)

	self:SetTall(8 + self.titleH + 6 + self.bodyH + 10)
end

function PANEL:PerformLayout()
	if (self.titleH) then
		self.body:SetPos(10, 8 + self.titleH + 6)
		self:SetTall(8 + self.titleH + 6 + self.bodyH + 10)
	end
end

function PANEL:Paint(w, h)
	surface.SetDrawColor(6, 5, 7, 245)
	surface.DrawRect(0, 0, w, h)
	surface.SetDrawColor(175, 24, 43, 220)
	surface.DrawOutlinedRect(0, 0, w, h, 1)
end

function PANEL:Think()
	-- Лист закрылся — тултипу больше не над чем висеть.
	if (!IsValid(self.guard)) then
		self:Remove()
		return
	end

	local left = input.IsMouseDown(MOUSE_LEFT)
	local right = input.IsMouseDown(MOUSE_RIGHT)
	if (SysTime() > self.armTime and ((left and !self.prevLeft) or (right and !self.prevRight))) then
		self:Remove()
		return
	end
	self.prevLeft, self.prevRight = left, right
end

vgui.Register("AfterlightVTMDescriptionTip", PANEL, "DPanel")

local currentTip

-- Меню Helix — панель-popup: VGUI рисует popup-панели поверх обычных
-- верхнеуровневых, а вручную рисуемое поддерево меню обрезало тултип рамкой.
-- Поэтому тултип создаётся верхнеуровневым и сам делается popup-ом (как Derma-
-- окна, открывающиеся поверх меню Helix); затем ввод отключается — клики
-- проходят сквозь тултип, а закрытие обрабатывает Think.
-- kind: "stats" | "disciplines"; guard — панель листа, владеющая тултипом.
function ix.vtm.descriptions.OpenTip(kind, id, level, guard)
	local name, text = ix.vtm.descriptions.Get(kind, id, level)
	if (!name or !IsValid(guard)) then return end

	if (IsValid(currentTip)) then
		currentTip:Remove()
		currentTip = nil
	end

	local definition = kind == "disciplines" and ix.disciplines.list[id] or ix.vtm.stats.list[id]
	local subjectName = definition and definition.name or id

	local tip = vgui.Create("AfterlightVTMDescriptionTip")
	tip.guard = guard
	tip:SetContent(string.format("%s — уровень %d: %s", subjectName, level, name), text)
	tip:MakePopup()
	tip:SetMouseInputEnabled(false)
	tip:SetKeyboardInputEnabled(false)

	local w, h = tip:GetWide(), tip:GetTall()
	local mx, my = gui.MousePos()
	local x = math.Clamp(mx + 14, 8, math.max(ScrW() - w - 8, 8))
	-- Описание раскрывается СВЕРХУ от курсора и всегда рядом с ним: читаемо и
	-- у последних строк листа, где вниз просто нет места. Вниз тултип уходит
	-- только когда сверху не помещается вовсе, и зажимается границами экрана.
	local y = my - h - 12
	if (y < 8) then
		y = math.Clamp(my + 18, 8, math.max(ScrH() - h - 8, 8))
	end
	tip:SetPos(x, y)
	currentTip = tip
	ix.vtm.descriptions.lastTip = tip
end
