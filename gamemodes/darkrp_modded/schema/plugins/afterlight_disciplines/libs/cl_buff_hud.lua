-- Правый верхний угол: иконка и обратный отсчёт каждой действующей
-- способности (Могущество любого уровня, усиление крови и т.д.), чтобы
-- игрок всегда видел, сколько бафф ещё продлится.
local PLUGIN = PLUGIN

local ICON_SIZE = 26
local materials = {}

local function GetIcon(path)
	local cached = materials[path]
	if (cached == nil) then
		cached = file.Exists("materials/" .. path, "GAME") and Material(path) or false
		materials[path] = cached
	end
	return cached or nil
end

-- Каждая запись знает, как по NW2-состоянию игрока понять «активно ли» и
-- сколько осталось. Новые способности добавляют свои записи сюда.
local buffEntries = {
	{
		icon = "afterlight/disciplines/icons/potence.png",
		GetRemaining = function(client)
			local level = client:GetNW2Int("afterlightPotenceLevel", 0)
			local ends = client:GetNW2Float("afterlightPotenceEnd", 0)
			if (level > 0 and ends > CurTime()) then
				return ends - CurTime(), "Могущество " .. level
			end
		end
	},
	{
		icon = "afterlight/disciplines/icons/vampire_abilities.png",
		GetRemaining = function(client)
			local ends = client:GetNW2Float("afterlightBloodBuffEnd", 0)
			if (ends > CurTime()) then
				return ends - CurTime(), "Усиление крови"
			end
		end
	}
}

local function FormatSeconds(remaining)
	remaining = math.max(math.ceil(remaining), 0)
	return string.format("%d:%02d", math.floor(remaining / 60), remaining % 60)
end

hook.Add("HUDPaint", "AfterlightDisciplineBuffHud", function()
	local client = LocalPlayer()
	if (!IsValid(client) or !client:Alive()) then return end

	local y = 16
	for _, entry in ipairs(buffEntries) do
		local remaining, label = entry.GetRemaining(client)
		if (remaining) then
			local text = label .. "  " .. FormatSeconds(remaining)
			surface.SetFont("ixSmallFont")
			local textWide = surface.GetTextSize(text)
			local rowWide = ICON_SIZE + 8 + textWide
			local x = ScrW() - 16 - rowWide

			local icon = GetIcon(entry.icon)
			if (icon) then
				surface.SetDrawColor(255, 255, 255, 235)
				surface.SetMaterial(icon)
				surface.DrawTexturedRect(x, y, ICON_SIZE, ICON_SIZE)
			end

			-- Подсветка последних пяти секунд.
			local color = remaining <= 5 and Color(215, 60, 70, 255) or Color(228, 220, 208, 255)
			draw.SimpleText(text, "ixSmallFont", x + ICON_SIZE + 8, y + ICON_SIZE * 0.5,
				color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

			y = y + ICON_SIZE + 8
		end
	end
end)
