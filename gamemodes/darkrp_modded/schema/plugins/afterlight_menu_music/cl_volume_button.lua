if (!CLIENT) then return end

--[[
	Иконка громкости Afterlight Music.

	В правом нижнем углу каждого экрана, где звучит музыка (заставка, меню
	персонажей, игровое меню Helix по TAB), стоит небольшая иконка динамика.
	Полоса громкости (AfterlightMusicVolume из cl_volume.lua) по умолчанию
	скрыта и появляется по клику на иконку; повторный клик убирает её обратно,
	колесо мыши на иконке меняет громкость и заодно показывает полосу, а через
	barIdleTime секунд бездействия полоса закрывается сама.

	Иконка рисуется векторно через surface.DrawPoly: материалы не нужны, вид
	одинаков на любом разрешении. Число дуг справа от динамика соответствует
	уровню громкости, при нулевой громкости вместо дуг рисуется перечёркивание.

	Как и полоса, иконка живёт внутри панели открытого экрана и умирает вместе
	с ней: MakePopup не вызывается, клавиатура не захватывается, вкладки Helix
	и кнопки меню продолжают работать.
]]

local MUSIC = AfterlightMusic

-- Признак загруженного модуля: полоса громкости скрывается только тогда, когда
-- есть чем её показать (см. cl_volume.lua, PANEL:IsRequested).
MUSIC.HasVolumeButton = true

-- Через сколько секунд бездействия полоса убирается сама. 0 — не убирать.
MUSIC.barIdleTime = 8

-- Состояние полосы. После lua_refresh контроллер собирает таблицу заново,
-- поэтому значение просто приводится к булеву.
MUSIC.bBarOpen = MUSIC.bBarOpen == true
MUSIC.barInteractionTime = CurTime()

-- Кнопка от предыдущей версии файла убирается, иначе в панелях скрытых меню
-- останутся лишние иконки.
if (IsValid(MUSIC.button)) then
	MUSIC.button:Remove()
end

MUSIC.button = nil

-- =========================================================
-- СОСТОЯНИЕ ПОЛОСЫ ГРОМКОСТИ
-- =========================================================

function MUSIC:IsVolumeBarOpen()
	return self.bBarOpen == true
end

function MUSIC:TouchVolumeBar()
	self.barInteractionTime = CurTime()
end

function MUSIC:SetVolumeBar(bOpen)
	local open = bOpen and true or false

	if (open == self.bBarOpen) then
		self:TouchVolumeBar()

		return
	end

	self.bBarOpen = open
	self:TouchVolumeBar()

	-- Полосу прячем — жест на ней нужно закончить, чтобы значение ушло в cookie.
	if (!open and IsValid(self.slider)) then
		self.slider:FinishDrag()
	end
end

function MUSIC:ToggleVolumeBar()
	self:SetVolumeBar(!self.bBarOpen)
end

-- Число дуг у иконки: 0 — звук выключен, дальше по третям шкалы.
function MUSIC:GetVolumeBands()
	if (self.volume <= 0.001) then
		return 0
	elseif (self.volume < 0.34) then
		return 1
	elseif (self.volume < 0.67) then
		return 2
	end

	return 3
end

-- Полоса убирается сама, когда курсор ушёл и жест закончен.
function MUSIC:UpdateVolumeBarIdle()
	if (!self.bBarOpen or self.barIdleTime <= 0) then
		return
	end

	local busy = (IsValid(self.slider) and (self.slider.dragging or self.slider:IsHovered()))
		or (IsValid(self.button) and self.button:IsHovered())

	if (busy) then
		self:TouchVolumeBar()

		return
	end

	if (CurTime() - (self.barInteractionTime or 0) >= self.barIdleTime) then
		self:SetVolumeBar(false)
	end
end

-- =========================================================
-- РИСОВАНИЕ ИКОНКИ
-- =========================================================

-- Дуга собирается лентой из четырёхугольников: surface.DrawLine рисует только
-- в один пиксель, и на крупной иконке это выглядело бы тонкой ниткой.
local function DrawArc(cx, cy, radius, spread, thickness, steps)
	steps = steps or 10

	local inner = radius - thickness * 0.5
	local outer = radius + thickness * 0.5

	for i = 1, steps do
		local from = -spread + spread * 2 * (i - 1) / steps
		local to = -spread + spread * 2 * i / steps

		surface.DrawPoly({
			{x = cx + math.cos(from) * inner, y = cy + math.sin(from) * inner},
			{x = cx + math.cos(to) * inner, y = cy + math.sin(to) * inner},
			{x = cx + math.cos(to) * outer, y = cy + math.sin(to) * outer},
			{x = cx + math.cos(from) * outer, y = cy + math.sin(from) * outer}
		})
	end
end

local function DrawBar(x1, y1, x2, y2, thickness)
	local dx, dy = x2 - x1, y2 - y1
	local length = math.sqrt(dx * dx + dy * dy)

	if (length <= 0) then
		return
	end

	local nx = -dy / length * thickness * 0.5
	local ny = dx / length * thickness * 0.5

	surface.DrawPoly({
		{x = x1 + nx, y = y1 + ny},
		{x = x2 + nx, y = y2 + ny},
		{x = x2 - nx, y = y2 - ny},
		{x = x1 - nx, y = y1 - ny}
	})
end

local PANEL = {}

function PANEL:Init()
	self:SetSize(self:GetTargetSize(), self:GetTargetSize())
	self:SetZPos(32767)
	self:SetMouseInputEnabled(true)
	self:SetKeyboardInputEnabled(false)
	self:SetCursor("hand")
	self:SetTooltip("Громкость музыки • клик — показать или скрыть полосу")

	self.emphasis = 0
	self.appear = 0
end

function PANEL:GetTargetSize()
	return math.Clamp(math.floor(ScrH() * 0.041), 34, 48)
end

-- Прозрачность наследуется от цепочки родителей: иконка гаснет вместе с меню.
function PANEL:GetVisibility()
	return self.appear * MUSIC:GetChainAlpha(self:GetParent())
end

function PANEL:IsInteractive()
	local parent = self:GetParent()

	if (!MUSIC:IsPanelOpen(parent)) then
		return false
	end

	return self:GetVisibility() > 0.05
end

function PANEL:OnMousePressed(code)
	if (code != MOUSE_LEFT or !self:IsInteractive()) then
		return
	end

	MUSIC:ToggleVolumeBar()
end

function PANEL:OnMouseWheeled(delta)
	if (!self:IsInteractive()) then
		return false
	end

	-- Колесом громкость меняется без раскрытия полосы — показываем её, чтобы
	-- изменение было видно.
	MUSIC:SetVolumeBar(true)
	MUSIC:SetVolume(MUSIC.volume + delta * 0.02, true)
	MUSIC:TouchVolumeBar()

	return true
end

function PANEL:OnRemove()
	if (MUSIC.button == self) then
		MUSIC.button = nil
	end

	-- Родителя могли удалить посреди жеста — значение не должно потеряться.
	if (MUSIC.bVolumeDirty) then
		MUSIC:SaveVolume()
	end
end

function PANEL:Think()
	local parent = self:GetParent()

	if (!IsValid(parent)) then
		return
	end

	-- Смена разрешения: поддерживаем размер без отдельного хука.
	local size = self:GetTargetSize()

	if (self:GetWide() != size or self:GetTall() != size) then
		self:SetSize(size, size)
	end

	-- Правый нижний угол родительской панели — тот же, что и у полосы.
	local marginX, marginY = MUSIC:GetCornerMargins(parent)

	self:SetPos(
		math.max(0, parent:GetWide() - self:GetWide() - marginX),
		math.max(0, parent:GetTall() - self:GetTall() - marginY)
	)

	local target = MUSIC:IsPanelOpen(parent) and 1 or 0
	self.appear = Lerp(math.Clamp(FrameTime() * 9, 0, 1), self.appear, target)

	MUSIC:UpdateVolumeBarIdle()
end

function PANEL:Paint(w, h)
	local visibility = self:GetVisibility()

	if (visibility <= 0.01) then
		return
	end

	-- Пока полоса открыта, иконка подсвечена — видно, чем она управляет.
	local active = self:IsHovered() or MUSIC.bBarOpen
	self.emphasis = Lerp(math.Clamp(FrameTime() * 14, 0, 1), self.emphasis, active and 1 or 0)

	local emphasis = self.emphasis
	local plate = (18 + 110 * emphasis) * visibility

	-- Музыка не играет — иконка приглушена, но остаётся читаемой.
	local dim = MUSIC.envelope > 0.02 and 1 or 0.55
	local ink = (95 + 140 * emphasis) * visibility * dim

	draw.RoundedBox(4, 0, 0, w, h, Color(8, 5, 7, plate))

	local midY = h * 0.5
	local cx = w * 0.30
	local halfThroat = h * 0.13
	local halfMouth = h * 0.30
	local bodyWidth = w * 0.16
	local coneX = cx + w * 0.16

	surface.SetDrawColor(215, 202, 191, ink)

	-- Корпус динамика: прямоугольник сразу переходит в раструб.
	surface.DrawPoly({
		{x = cx - bodyWidth, y = midY - halfThroat},
		{x = cx, y = midY - halfThroat},
		{x = coneX, y = midY - halfMouth},
		{x = coneX, y = midY + halfMouth},
		{x = cx, y = midY + halfThroat},
		{x = cx - bodyWidth, y = midY + halfThroat}
	})

	local bands = MUSIC:GetVolumeBands()

	if (bands == 0) then
		DrawBar(coneX + w * 0.06, midY - h * 0.20, coneX + w * 0.30, midY + h * 0.20,
			math.max(2, w * 0.055))

		return
	end

	local spread = math.rad(48)
	local thickness = math.max(1.6, w * 0.045)

	for i = 1, bands do
		DrawArc(coneX, midY, w * (0.11 + 0.085 * i), spread, thickness, 10)
	end
end

vgui.Register("AfterlightMusicVolumeButton", PANEL, "DPanel")

-- =========================================================
-- РАЗМЕЩЕНИЕ ИКОНКИ
-- =========================================================

-- Хост ищется тем же способом, что и для полосы (MUSIC:FindHost), поэтому
-- иконка и полоса всегда оказываются в одном и том же открытом экране.
function MUSIC:UpdateVolumeButton()
	if (!IsValid(self.button)) then
		self.button = nil
	end

	local host = self:FindHost()

	if (!IsValid(host)) then
		if (IsValid(self.button)) then
			self.button:Remove()
		end

		self.button = nil

		return
	end

	if (!IsValid(self.button)) then
		-- Как и полосу, иконку создаём через vgui.Create: ixSubpanelParent:Add
		-- помечает детей как painted manually, и иконка перестала бы рисоваться.
		self.button = vgui.Create("AfterlightMusicVolumeButton", host)
	elseif (self.button:GetParent() != host) then
		self.button:SetParent(host)
		self.button:MoveToFront()
	end
end

-- =========================================================
-- ОТЛАДОЧНАЯ КОМАНДА
-- =========================================================

concommand.Add("afterlight_music_bar", function(_, _, arguments)
	local argument = string.lower(arguments[1] or "toggle")

	if (argument == "toggle") then
		MUSIC:ToggleVolumeBar()
	elseif (argument == "0") then
		MUSIC:SetVolumeBar(false)
	elseif (argument == "1") then
		MUSIC:SetVolumeBar(true)
	else
		MsgN("[Afterlight Music] Использование: afterlight_music_bar <0|1|toggle>")

		return
	end

	MsgN("[Afterlight Music] Полоса громкости: ", MUSIC.bBarOpen and "открыта" or "скрыта")
end)
