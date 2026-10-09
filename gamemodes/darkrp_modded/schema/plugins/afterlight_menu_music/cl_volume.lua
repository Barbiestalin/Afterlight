if (!CLIENT) then return end

--[[
	Полоса громкости Afterlight Music.

	Контрол один на весь проект: он живёт внутри того экрана, который сейчас
	открыт (заставка, меню персонажей или игровое меню Helix), и умирает вместе
	с ним. Собственных popup-панелей и HUD-элементов контрол не создаёт,
	MakePopup не вызывает и клавиатуру не забирает, поэтому не мешает вкладкам
	Helix и кнопкам меню.

	По умолчанию полоса скрыта: в правом нижнем углу стоит иконка динамика
	(AfterlightMusicVolumeButton, cl_volume_button.lua), а полоса появляется
	над ней по клику на иконку. Иконка и полоса стоят в одном углу экрана,
	поэтому панель занимает весь экран — угол панели и есть угол экрана.
]]

local MUSIC = AfterlightMusic

-- Хосты в порядке приоритета: берётся первая подходящая панель. Список можно
-- дополнить, если схема заводит собственные панели поверх игры.
MUSIC.hosts = MUSIC.hosts or {
	{
		name = "intro",
		get = function()
			return AfterlightIntro and AfterlightIntro.frame
		end
	},
	{
		name = "menu",
		get = function()
			return ix and ix.gui and ix.gui.menu
		end
	},
	{
		name = "characterMenu",
		get = function()
			return ix and ix.gui and ix.gui.characterMenu
		end
	}
}

-- Lua refresh: прежний экземпляр убираем, иначе останутся ползунки в панелях
-- скрытых меню.
if (IsValid(MUSIC.slider)) then
	MUSIC.slider:Remove()
end

MUSIC.slider = nil

-- Отступы от правого нижнего угла панели-хоста. Иконка громкости и полоса
-- стоят в одном углу, поэтому формула у них общая.
function MUSIC:GetCornerMargins(panel)
	local width = IsValid(panel) and panel:GetWide() or ScrW()
	local height = IsValid(panel) and panel:GetTall() or ScrH()

	-- Отступ снизу чуть больше, чтобы не наезжать на подпись версии в углу меню
	-- персонажей Helix.
	return math.Clamp(math.floor(width * 0.012), 12, 28),
		math.Clamp(math.floor(height * 0.022), 24, 34)
end

local PANEL = {}

function PANEL:Init()
	self:SetSize(self:GetTargetWidth(), self:GetTargetHeight())
	self:SetZPos(32767)
	-- Мышь включается вместе с полосой: пока она скрыта, нажатия в этом углу
	-- должны доставаться интерфейсу под ней.
	self:SetMouseInputEnabled(false)
	self:SetKeyboardInputEnabled(false)
	self:SetCursor("hand")

	self.dragging = false
	self.emphasis = 0
	self.appear = 0
	-- 0 — полоса убрана (иконка не нажата), 1 — показана.
	self.open = 0
end

-- Нужна ли полоса прямо сейчас. Если модуль иконки не загрузился, полоса
-- остаётся видимой постоянно — громкость можно менять в любом случае.
function PANEL:IsRequested()
	if (!MUSIC.HasVolumeButton) then
		return true
	end

	return MUSIC.bBarOpen == true
end

function PANEL:GetTargetWidth()
	return math.Clamp(math.floor(ScrW() * 0.11), 152, 212)
end

function PANEL:GetTargetHeight()
	return math.Clamp(math.floor(ScrH() * 0.045), 38, 50)
end

-- Прозрачность наследуется от всей цепочки родителей: так контрол гаснет
-- вместе с меню, которое его содержит. Множитель open отвечает за плавное
-- раскрытие полосы по клику на иконку.
function PANEL:GetVisibility()
	return self.appear * self.open * MUSIC:GetChainAlpha(self:GetParent())
end

function PANEL:IsInteractive()
	local parent = self:GetParent()

	if (!MUSIC:IsPanelOpen(parent)) then
		return false
	end

	-- Скрытая полоса не откликается: иначе она ловила бы клики в углу меню.
	if (self.open <= 0.05) then
		return false
	end

	return self:GetVisibility() > 0.05
end

function PANEL:FinishDrag()
	if (!self.dragging) then
		return
	end

	self.dragging = false
	self:MouseCapture(false)

	-- Жест закончился — фиксируем значение в cookie.
	MUSIC:SaveVolume()
end

-- Любой жест на полосе откладывает её автоматическое закрытие по простою.
function PANEL:TouchIdle()
	if (MUSIC.TouchVolumeBar) then
		MUSIC:TouchVolumeBar()
	end
end

function PANEL:UpdateFromCursor()
	local x = self:CursorPos()
	local inset = math.floor(self:GetWide() * 0.06)

	MUSIC:SetVolume((x - inset) / math.max(self:GetWide() - inset * 2, 1), true)
	self:TouchIdle()
end

function PANEL:OnMousePressed(code)
	if (code != MOUSE_LEFT or !self:IsInteractive()) then
		return
	end

	self.dragging = true
	self:MouseCapture(true)
	self:UpdateFromCursor()
end

function PANEL:OnCursorMoved()
	if (!self.dragging) then
		return
	end

	if (!self:IsInteractive()) then
		self:FinishDrag()

		return
	end

	self:UpdateFromCursor()
end

function PANEL:OnMouseReleased(code)
	if (code != MOUSE_LEFT) then
		return
	end

	if (self.dragging and self:IsInteractive()) then
		self:UpdateFromCursor()
	end

	self:FinishDrag()
end

function PANEL:OnMouseWheeled(delta)
	if (!self:IsInteractive()) then
		return false
	end

	MUSIC:SetVolume(MUSIC.volume + delta * 0.02, true)
	self:TouchIdle()

	return true
end

function PANEL:OnRemove()
	if (self.dragging) then
		self.dragging = false
		self:MouseCapture(false)
	end

	if (MUSIC.slider == self) then
		MUSIC.slider = nil
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
	local width, height = self:GetTargetWidth(), self:GetTargetHeight()

	if (self:GetWide() != width or self:GetTall() != height) then
		self:SetSize(width, height)
	end

	-- Правый нижний угол родительской панели: полоса стоит над иконкой.
	local marginX, marginY = MUSIC:GetCornerMargins(parent)
	local lift = 0

	if (IsValid(MUSIC.button) and MUSIC.button:GetParent() == parent) then
		local size = MUSIC.button:GetTall()

		lift = size + math.max(6, math.floor(size * 0.22))
	end

	-- Раскрытие по клику на иконку: полоса слегка приподнимается, пока растёт.
	local openTarget = (self:IsRequested() and MUSIC:IsPanelOpen(parent)) and 1 or 0
	self.open = Lerp(math.Clamp(FrameTime() * 12, 0, 1), self.open, openTarget)

	self:SetPos(
		math.max(0, parent:GetWide() - self:GetWide() - marginX),
		math.max(0, parent:GetTall() - self:GetTall() - marginY - lift
			- math.floor(8 * (1 - self.open)))
	)

	-- Плавное появление и уход вместе с родительским интерфейсом.
	local target = MUSIC:IsPanelOpen(parent) and 1 or 0
	self.appear = Lerp(math.Clamp(FrameTime() * 9, 0, 1), self.appear, target)

	-- Мышь включена только у раскрытой полосы: скрытая не должна ловить клики
	-- в углу меню.
	self:SetMouseInputEnabled(!self.dragging and self.open > 0.05)

	if (self.dragging and (!input.IsMouseDown(MOUSE_LEFT) or !self:IsInteractive())) then
		self:FinishDrag()
	end
end

function PANEL:Paint(w, h)
	local visibility = self:GetVisibility()

	if (visibility <= 0.01) then
		return
	end

	local active = self:IsHovered() or self.dragging
	self.emphasis = Lerp(math.Clamp(FrameTime() * 14, 0, 1), self.emphasis, active and 1 or 0)

	local emphasis = self.emphasis

	-- В покое контрол едва заметен, под курсором проявляется.
	local plate = (18 + 110 * emphasis) * visibility
	local ink = (95 + 140 * emphasis) * visibility
	local track = (55 + 65 * emphasis) * visibility

	local value = MUSIC.volume
	local inset = math.floor(w * 0.06)
	local trackWidth = w - inset * 2
	local trackY = h - 15
	local knobX = inset + trackWidth * value

	draw.RoundedBox(4, 0, 0, w, h, Color(8, 5, 7, plate))

	draw.SimpleText("МУЗЫКА", "DermaDefault", inset, 7, Color(190, 181, 174, ink))

	draw.SimpleText(math.Round(value * 100) .. "%", "DermaDefault", w - inset, 7,
		Color(190, 181, 174, ink), TEXT_ALIGN_RIGHT)

	surface.SetDrawColor(155, 145, 141, track)
	surface.DrawRect(inset, trackY, trackWidth, 2)

	surface.SetDrawColor(145, 64, 75, ink)
	surface.DrawRect(inset, trackY, trackWidth * value, 2)

	draw.RoundedBox(3, knobX - 3, trackY - 4, 6, 10, Color(215, 202, 191, ink))
end

vgui.Register("AfterlightMusicVolume", PANEL, "DPanel")

-- =========================================================
-- РАЗМЕЩЕНИЕ КОНТРОЛОВ В ОТКРЫТОМ ЭКРАНЕ
-- =========================================================

function MUSIC:FindHost()
	for _, info in ipairs(self.hosts) do
		local panel = info.get()

		if (self:IsHostUsable(panel)) then
			return panel, info.name
		end
	end

	return nil
end

function MUSIC:IsHostUsable(panel)
	if (!IsValid(panel)) then
		return false
	end

	-- Если контрол уже живёт в этой панели, остаёмся в ней, пока она видна:
	-- так он уходит вместе со своим интерфейсом, а не пропадает рывком.
	if (IsValid(self.slider) and self.slider:GetParent() == panel) then
		return panel:IsVisible() and panel:GetAlpha() > 0
	end

	return self:IsPanelOpen(panel)
end

function MUSIC:UpdateSliderHost()
	-- Иконка размещается первой: полоса в PANEL:Think равняется на неё.
	if (self.UpdateVolumeButton) then
		self:UpdateVolumeButton()
	end

	if (!IsValid(self.slider)) then
		self.slider = nil
	end

	-- Helix прячет детей закрывающегося меню (ixCharMenu:Close обходит детей и
	-- вызывает SetVisible(false)), а у скрытой панели Think не вызывается.
	-- Поэтому захват мыши освобождаем отсюда — иначе курсор останется зажатым.
	if (IsValid(self.slider) and self.slider.dragging and !self.slider:IsInteractive()) then
		self.slider:FinishDrag()
	end

	local host, hostName = self:FindHost()

	if (!IsValid(host)) then
		if (IsValid(self.slider)) then
			self.slider:Remove()
		end

		self.slider = nil
		self.sliderHost = nil

		return
	end

	if (!IsValid(self.slider)) then
		-- Важно создавать через vgui.Create: ixSubpanelParent:Add помечает детей
		-- как painted manually, и контрол перестал бы рисоваться в меню Helix.
		self.slider = vgui.Create("AfterlightMusicVolume", host)
	elseif (self.slider:GetParent() != host) then
		self.slider:FinishDrag()
		self.slider:SetParent(host)
		self.slider:MoveToFront()
	end

	self.sliderHost = hostName
end
