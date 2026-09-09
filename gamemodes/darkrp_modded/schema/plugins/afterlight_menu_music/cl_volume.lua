if (!CLIENT) then return end

-- Один контрол для всех экранов; никаких самостоятельных popup/HUD-панелей.
local MUSIC = AfterlightMusic

-- Lua refresh: удалить прежние экземпляры, включая панели скрытых меню.
for panel in pairs(MUSIC.volumeSliders or {}) do
	if (IsValid(panel)) then panel:Remove() end
end
MUSIC.volumeSliders = setmetatable({}, {__mode = "k"})

local PANEL = {}

function PANEL:Init()
	self:SetSize(196, 48)
	self:SetZPos(32767)
	self:SetMouseInputEnabled(true)
	self:SetKeyboardInputEnabled(false)
	self:SetCursor("hand")
	self:SetTooltip("Громкость музыки • перетаскивание или колесо мыши")
	self.emphasis = 0
end

function PANEL:IsHostVisible()
	local parent = self:GetParent()

	while (IsValid(parent)) do
		if (!parent:IsVisible() or parent:GetAlpha() <= 0) then return false end
		parent = parent:GetParent()
	end

	return true
end

function PANEL:FinishDrag()
	if (!self.dragging) then return end
	self.dragging = false
	self:MouseCapture(false)
	MUSIC:SetVolume(MUSIC.volume)
end

function PANEL:UpdateFromCursor()
	local x = self:CursorPos()
	MUSIC:SetVolume((x - 12) / math.max(self:GetWide() - 24, 1), true)
end

function PANEL:OnMousePressed(code)
	if (code != MOUSE_LEFT or !self:IsHostVisible()) then return end
	self.dragging = true
	self:MouseCapture(true)
	self:UpdateFromCursor()
end

function PANEL:OnCursorMoved()
	if (self.dragging) then
		if (!self:IsHostVisible()) then self:FinishDrag() return end
		self:UpdateFromCursor()
	end
end

function PANEL:OnMouseReleased(code)
	if (code != MOUSE_LEFT) then return end
	if (self.dragging and self:IsHostVisible()) then self:UpdateFromCursor() end
	self:FinishDrag()
end

function PANEL:OnMouseWheeled(delta)
	if (!self:IsHostVisible()) then return false end
	MUSIC:SetVolume(MUSIC.volume + delta * 0.02)
	return true
end

function PANEL:OnRemove()
	self:FinishDrag()
	MUSIC.volumeSliders[self] = nil
end

function PANEL:Think()
	local parent = self:GetParent()
	if (!IsValid(parent)) then return end

	-- Не подменяем PerformLayout/Think Helix; поддерживаем изменение разрешения.
	local margin = math.Clamp(math.floor(parent:GetTall() * 0.025), 12, 28)
	self:SetPos(math.max(0, parent:GetWide() - self:GetWide() - margin),
		math.max(0, parent:GetTall() - self:GetTall() - margin))

	if (self.dragging and (!input.IsMouseDown(MOUSE_LEFT) or !self:IsHostVisible())) then
		self:FinishDrag()
	end
end

function PANEL:Paint(w, h)
	local active = self:IsHovered() or self.dragging
	self.emphasis = Lerp(math.Clamp(FrameTime() * 14, 0, 1), self.emphasis, active and 1 or 0)
	local emphasis = self.emphasis
	local alpha = 95 + 140 * emphasis
	local value = MUSIC.volume
	local x = 12 + (w - 24) * value

	draw.RoundedBox(4, 0, 0, w, h, Color(8, 5, 7, 18 + 110 * emphasis))
	draw.SimpleText("МУЗЫКА", "DermaDefault", 12, 7, Color(190, 181, 174, alpha))
	draw.SimpleText(math.Round(value * 100) .. "%", "DermaDefault", w - 12, 7,
		Color(190, 181, 174, alpha), TEXT_ALIGN_RIGHT)

	surface.SetDrawColor(155, 145, 141, 55 + 65 * emphasis)
	surface.DrawRect(12, 33, w - 24, 2)
	surface.SetDrawColor(145, 64, 75, alpha)
	surface.DrawRect(12, 33, (w - 24) * value, 2)
	draw.RoundedBox(3, x - 3, 29, 6, 10, Color(215, 202, 191, alpha))
end

vgui.Register("AfterlightMusicVolume", PANEL, "DPanel")

function MUSIC:AttachVolumeSlider(parent)
	if (!IsValid(parent)) then return end
	if (IsValid(parent.afterlightVolumeSlider)) then return parent.afterlightVolumeSlider end

	local slider = vgui.Create("AfterlightMusicVolume", parent)
	parent.afterlightVolumeSlider = slider
	self.volumeSliders[slider] = true
	return slider
end

hook.Add("Think", "AfterlightMusicVolumeMenus", function()
	-- Интро может загружаться раньше музыкального плагина.
	if (AfterlightIntro and IsValid(AfterlightIntro.frame)) then
		MUSIC:AttachVolumeSlider(AfterlightIntro.frame)
	end

	if (ix and ix.gui) then
		for _, key in ipairs({"characterMenu", "menu", "mainMenu", "tabMenu"}) do
			local parent = ix.gui[key]
			if (IsValid(parent)) then MUSIC:AttachVolumeSlider(parent) end
		end
	end

	-- Think скрытых дочерних панелей может не вызываться: освобождаем capture здесь.
	for slider in pairs(MUSIC.volumeSliders) do
		if (IsValid(slider) and slider.dragging and !slider:IsHostVisible()) then
			slider:FinishDrag()
		end
	end
end)
