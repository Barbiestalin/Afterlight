--[[
	Слой Helix для стенда: пространство имён ix, базовые Derma-классы и те
	панели Helix, которые не относятся к проверяемому жизненному циклу
	(создание/загрузка персонажа). Всё остальное — ixSubpanelParent,
	ixCharMenuPanel, ixCharMenuMain, ixCharMenu, ixMenuButton, ixMenu,
	ixIntro, ixNoticeBar и система анимаций Helix — загружается из настоящих
	исходников Helix (см. run.lua).
]]

local env = ...

-- =========================================================
-- базовые Derma-классы
-- =========================================================

env.vgui.Register("EditablePanel", {}, "Panel")
env.vgui.Register("DPanel", {}, "EditablePanel")
env.vgui.Register("DLabel", {}, "Panel")
env.vgui.Register("DImage", {}, "DPanel")

local dButton = {}

function dButton:Init()
	self:SetPaintBackground(true)
end

function dButton:DoClick()
end

env.vgui.Register("DButton", dButton, "DLabel")

local dScrollPanel = {}

function dScrollPanel:Init()
	self.m_vbar = env.vgui.Create("Panel", self)
	self.m_vbar:SetWide(8)
	self.m_canvas = env.vgui.Create("Panel", self)
end

env.vgui.Register("DScrollPanel", dScrollPanel, "DPanel")

local dFrame = {}

function dFrame:Init()
	self:SetSize(300, 200)
	self:SetTitle("Window")
end

env.vgui.Register("DFrame", dFrame, "EditablePanel")
env.vgui.Register("DTextEntry", {}, "Panel")

function env.CloseDermaMenus()
end

-- =========================================================
-- расширения строк GLua
-- =========================================================

if (!string.utf8upper) then
	function string.utf8upper(self)
		return (tostring(self)):upper()
	end
end

if (!string.utf8lower) then
	function string.utf8lower(self)
		return (tostring(self)):lower()
	end
end

-- =========================================================
-- пространство имён ix
-- =========================================================

env.ix = env.ix or {util = {}, gui = {}, meta = {}, plugin = {}}

local ix = env.ix

ix.gui = ix.gui or {}
ix.config = ix.config or {}
ix.option = ix.option or {}
ix.faction = ix.faction or {indices = {}}
ix.char = ix.char or {loaded = {}}
ix.characters = {1001, 1002}
ix.plugin.list = ix.plugin.list or {}
ix.lang = ix.lang or {}
ix.data = {Get = function() return nil end, Set = function() end}
ix.item = {}
ix.net = {}
ix.voice = {}

local configValues = {
	music = "music/hl2_song2.mp3",
	color = env.Color(140, 140, 140, 255),
	maxCharacters = 5,
	communityURL = "",
	communityText = "",
	intro = true,
	cheapBlur = false,
	font = "Roboto Th",
	genericFont = "Roboto"
}

function ix.config.Get(name, default)
	local value = configValues[name]

	if (value == nil) then
		return default
	end

	return value
end

function ix.config.Add()
end

local optionValues = {
	animationScale = 1,
	disableAnimations = false,
	escCloseMenu = false,
	showIntro = true,
	cheapBlur = false,
	altLower = false
}

function ix.option.Get(name, default)
	local value = optionValues[name]

	if (value == nil) then
		return default
	end

	return value
end

function ix.option.Set(name, value)
	optionValues[name] = value

	return true
end

function ix.option.Add()
end

ix.util.DrawBlur = function() end

ix.util.GetMaterial = function()
	return nil
end

ix.util.StripRealmPrefix = function(name)
	return (name:gsub("^(sh_)", ""))
end

function ix.util.Include()
end

function ix.util.IncludeDir()
end

function ix.lang.LoadFromDir()
end

ix.plugin.Load = function() end
ix.plugin.LoadFromDir = function() end
ix.plugin.LoadEntities = function() end
ix.plugin.Initialize = function() end

function env.L(key)
	return tostring(key)
end

function env.L2()
	return nil
end

env.Schema = {
	name = "DarkRP Modded",
	description = "Afterlight",
	logo = nil
}

env.GAMEMODE = {
	Name = "darkrp_modded",
	Version = "1.0.0"
}

-- =========================================================
-- панели Helix, не связанные с жизненным циклом меню
-- =========================================================

-- Регистрация отложена: базовый ixCharMenuPanel появляется вместе с настоящим
-- cl_character.lua, а сам класс нужен только в момент создания меню.
function env.__registerCharSubpanelStubs()
	local charSubpanel = {}

	function charSubpanel:Init()
		self:SetSize(600, 400)
		self:SetPos(0, 0)
	end

	function charSubpanel:SlideDown()
	end

	function charSubpanel:SlideUp()
	end

	function charSubpanel:SetActiveSubpanel()
	end

	function charSubpanel:OnCharacterDeleted()
	end

	env.vgui.Register("ixCharMenuNew", charSubpanel, "ixCharMenuPanel")
	env.vgui.Register("ixCharMenuLoad", charSubpanel, "ixCharMenuPanel")
end

return env
