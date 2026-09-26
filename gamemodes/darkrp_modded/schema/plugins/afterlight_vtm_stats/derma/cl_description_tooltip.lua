if (!CLIENT) then return end

-- Таблица создаётся и в libs/cl_descriptions.lua; здесь страховка от любого
-- порядка включения файлов плагина.
ix.vtm = ix.vtm or {}
ix.vtm.descriptions = ix.vtm.descriptions or {}

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
	self.title:SetAutoStretchVertical(true)

	self.body = self:Add("DLabel")
	self.body:SetFont("ixSmallFont")
	self.body:SetTextColor(Color(225, 220, 212))
	self.body:SetWrap(true)
	self.body:SetAutoStretchVertical(true)
end

function PANEL:SetContent(titleText, bodyText, width)
	width = width or 340
	self:SetWide(width)
	self.title:SetPos(10, 8)
	self.title:SetWide(width - 20)
	self.title:SetText(titleText)
	self.body:SetPos(10, 8)
	self.body:SetWide(width - 20)
	self.body:SetText(bodyText)
	self:InvalidateLayout(true)
end

function PANEL:PerformLayout()
	local titleHeight = self.title:GetTall()
	self.body:SetPos(10, 8 + titleHeight + 6)
	local needed = 8 + titleHeight + 6 + self.body:GetTall() + 10
	if (needed != self:GetTall()) then
		self:SetTall(needed)
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

-- Меню Helix рисует своё содержимое вручную (SetPaintedManually + PaintManual),
-- поэтому тултип обязан жить внутри того же поддерева, что и лист: крепим его
-- к самой панели листа. Тогда он рисуется в том же проходе поверх строк листа
-- и в окне персонажа, и в создании персонажа, и в админ-листе.
-- Лист живёт в вручную рисуемом поддереве меню и может быть обрезан любым
-- предком (субпанель меню, скролл и т.п.). Видимая область = пересечение
-- границ всех предков, переведённое в координаты листа.
local function VisibleRect(panel)
	local x1, y1 = panel:LocalToScreen(0, 0)
	local x2, y2 = panel:LocalToScreen(panel:GetWide(), panel:GetTall())
	local parent = panel:GetParent()
	while (IsValid(parent)) do
		local px1, py1 = parent:LocalToScreen(0, 0)
		local px2, py2 = parent:LocalToScreen(parent:GetWide(), parent:GetTall())
		x1, y1 = math.max(x1, px1), math.max(y1, py1)
		x2, y2 = math.min(x2, px2), math.min(y2, py2)
		parent = parent:GetParent()
	end
	local vx1, vy1 = panel:ScreenToLocal(x1, y1)
	local vx2, vy2 = panel:ScreenToLocal(x2, y2)
	return vx1, vy1, vx2 - vx1, vy2 - vy1
end

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

	local tip = guard:Add("AfterlightVTMDescriptionTip")
	tip.guard = guard
	tip:SetContent(string.format("%s — уровень %d: %s", subjectName, level, name), text)

	local viewX, viewY, viewW, viewH = VisibleRect(guard)
	local mx, my = gui.MousePos()
	local lx, ly = guard:ScreenToLocal(mx, my)
	local w, h = tip:GetWide(), tip:GetTall()
	local x = math.Clamp(lx + 14, viewX + 4, math.max(viewX + viewW - w - 4, viewX + 4))
	local y = ly + 14
	if (y + h > viewY + viewH - 4) then
		y = ly - h - 10
	end
	y = math.Clamp(y, viewY + 4, math.max(viewY + viewH - h - 4, viewY + 4))
	tip:SetPos(x, y)
	currentTip = tip
	ix.vtm.descriptions.lastTip = tip
end
