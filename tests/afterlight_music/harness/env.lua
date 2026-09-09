--[[
	Мини-модель клиентского Garry's Mod для проверки плагинов Afterlight.

	Задача стенда — исполнять РЕАЛЬНЫЕ исходники Helix (панели ixCharMenu,
	ixMenu, ixIntro, система анимаций Helix) и РЕАЛЬНЫЙ код плагинов, а не их
	пересказ. Поэтому здесь реализованы только те части движка, от которых
	зависит поведение панелей и звука:

	  * дерево панелей VGUI (родитель/потомки, видимость, alpha, ZPos, Think,
	    Paint, Remove вместе с детьми, MouseCapture, CursorPos);
	  * виртуальные часы и покадровый насос (таймеры, хук Think, анимации);
	  * sound.PlayFile с каналом IChannel (Play/Pause/Stop/SetVolume/GetTime);
	  * cookie, hook, timer, input, gui, surface/draw как no-op.

	Файл возвращает окружение ENV, в которое загружаются GLua-скрипты.
]]

local env = {}

-- realm: стенд исполняет клиентскую часть
env.CLIENT = true
env.SERVER = false
env.MENU_DLL = false
env.GMOD = true

-- Стандартная библиотека Lua остаётся доступной загружаемым скриптам.
setmetatable(env, {__index = _G})

-- =========================================================
-- ПЕРЕВОД GLua -> Lua 5.1 (не равенства, оператор !, continue)
-- =========================================================

-- Переводчик GLua -> Lua 5.1 подключается из glua.lua (run.lua кладёт его в
-- env.__translate до загрузки этого файла).

local function translate(source)
	return assert(env.__translate, "не задан env.__translate")(source)
end

-- =========================================================
-- ЧАСЫ И НАСОС КАДРОВ
-- =========================================================

local clock = {time = 10, real = 10, frameTime = 1 / 60}
local timers = {}
local panelList = {}
local alphaAnims = {}
local mouseDown = {}
local keyDown = {}
local cursorX, cursorY = 0, 0
local screenClicker = false

env.__state = {
	clock = clock,
	timers = timers,
	panels = panelList,
	channels = {},
	cookies = {},
	mouseDown = mouseDown,
	keyDown = keyDown
}

function env.CurTime()
	return clock.time
end

function env.RealTime()
	return clock.real
end

function env.SysTime()
	return clock.real
end

function env.FrameTime()
	return clock.frameTime
end

function env.UnPredictedCurTime()
	return clock.time
end

local function setCursor(x, y)
	cursorX, cursorY = x, y
end

env.__setCursor = setCursor

function env.__isMouseDown(code)
	return mouseDown[code] == true
end

-- =========================================================
-- БАЗОВЫЕ ФУНКЦИИ
-- =========================================================

function env.ScrW()
	return env.__screenW
end

function env.ScrH()
	return env.__screenH
end

env.__screenW = 1920
env.__screenH = 1080

function env.ScreenScale(value)
	return value * (env.__screenW / 640)
end

function env.Lerp(fraction, from, to)
	return from + (to - from) * fraction
end

-- =========================================================
-- расширения стандартной библиотеки из GLua
-- =========================================================

function math.Clamp(value, min, max)
	if (value < min) then
		return min
	end

	if (value > max) then
		return max
	end

	return value
end

function math.Round(value, decimals)
	local mult = 10 ^ (decimals or 0)

	return math.floor(value * mult + 0.5) / mult
end

function math.Approach(current, target, delta)
	if (current < target) then
		return math.min(current + delta, target)
	end

	return math.max(current - delta, target)
end

function math.NormalizeAngle(angle)
	return (angle + 180) % 360 - 180
end

function math.Rand(min, max)
	return min + (max - min) * math.random()
end

function math.EaseInOut(progress, easeIn, easeOut)
	return progress
end

function string.Split(text, delimiter)
	local result = {}
	local pattern = "([^" .. (delimiter or " ") .. "]+)"

	for part in tostring(text):gmatch(pattern) do
		result[#result + 1] = part
	end

	return result
end

string.Explode = string.Split

function string.Trim(text)
	return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

function string.TrimLeft(text)
	return (tostring(text):gsub("^%s+", ""))
end

function string.TrimRight(text)
	return (tostring(text):gsub("%s+$", ""))
end

function string.Replace(text, find, replace)
	return (tostring(text):gsub(find, replace))
end

function table.HasValue(tbl, value)
	for _, existing in pairs(tbl) do
		if (existing == value) then
			return true
		end
	end

	return false
end

table.HasVal = table.HasValue

function table.Count(tbl)
	local total = 0

	for _ in pairs(tbl) do
		total = total + 1
	end

	return total
end

function table.Add(target, source)
	for _, value in ipairs(source or {}) do
		target[#target + 1] = value
	end

	return target
end

function table.Empty(tbl)
	for key in pairs(tbl) do
		tbl[key] = nil
	end
end

function table.Copy(source)
	local copy = {}

	for key, value in pairs(source) do
		copy[key] = type(value) == "table" and table.Copy(value) or value
	end

	return copy
end

function table.Random(tbl)
	local keys = {}

	for key in pairs(tbl) do
		keys[#keys + 1] = key
	end

	return tbl[keys[math.random(#keys)]]
end

function env.istable(value)
	return type(value) == "table"
end

function env.isstring(value)
	return type(value) == "string"
end

function env.isnumber(value)
	return type(value) == "number"
end

function env.isfunction(value)
	return type(value) == "function"
end

function env.isbool(value)
	return type(value) == "boolean"
end

function env.isvector(value)
	return false
end

function env.isangle(value)
	return false
end

function env.IsColor(value)
	return type(value) == "table" and value.r ~= nil
end

function env.tobool(value)
	if (value == nil or value == false or value == 0 or value == "0" or value == "false") then
		return false
	end

	return true
end

function env.SortedPairs(tbl, descending)
	local keys = {}

	for key in pairs(tbl) do
		keys[#keys + 1] = key
	end

	table.sort(keys, function(a, b)
		if (descending) then
			return a > b
		end

		return a < b
	end)

	local index = 0

	return function()
		index = index + 1
		local key = keys[index]

		if (key == nil) then
			return nil
		end

		return key, tbl[key]
	end
end

function env.Color(r, g, b, a)
	return {r = r or 255, g = g or 255, b = b or 255, a = a == nil and 255 or a}
end

function env.ColorAlpha(color, alpha)
	return {r = color.r, g = color.g, b = color.b, a = alpha}
end

function env.IsValid(object)
	return type(object) == "table" and object.__isValid == true
end

function env.MsgN(...)
	if (env.__verbose) then
		print(...)
	end
end

function env.Msg(...)
	if (env.__verbose) then
		io.write(...)
	end
end

function env.ErrorNoHalt(...)
	env.__errors[#env.__errors + 1] = table.concat({...}, " ")
end

env.__errors = {}

function env.Material(path)
	return {
		__isMaterial = true,
		GetName = function() return path end,
		Width = function() return 512 end,
		Height = function() return 512 end,
		IsError = function() return false end
	}
end

local vectorMeta = {}
vectorMeta.__index = vectorMeta

local function vectorOf(value)
	if (type(value) == "table") then
		return value
	end

	return setmetatable({x = value, y = value, z = value}, vectorMeta)
end

vectorMeta.__mul = function(a, b)
	local vector, scale = vectorOf(a), tonumber(b) or tonumber(a) or 1
	local other = type(a) == "table" and b or a

	if (type(other) == "table") then
		return setmetatable({x = vector.x * other.x, y = vector.y * other.y, z = vector.z * other.z}, vectorMeta)
	end

	return setmetatable({x = vector.x * scale, y = vector.y * scale, z = vector.z * scale}, vectorMeta)
end

vectorMeta.__div = function(a, b)
	local vector = vectorOf(a)
	local scale = tonumber(b) or 1

	return setmetatable({x = vector.x / scale, y = vector.y / scale, z = vector.z / scale}, vectorMeta)
end

vectorMeta.__add = function(a, b)
	local left, right = vectorOf(a), vectorOf(b)

	return setmetatable({x = left.x + right.x, y = left.y + right.y, z = left.z + right.z}, vectorMeta)
end

vectorMeta.__sub = function(a, b)
	local left, right = vectorOf(a), vectorOf(b)

	return setmetatable({x = left.x - right.x, y = left.y - right.y, z = left.z - right.z}, vectorMeta)
end

vectorMeta.__unm = function(a)
	local vector = vectorOf(a)

	return setmetatable({x = -vector.x, y = -vector.y, z = -vector.z}, vectorMeta)
end

vectorMeta.__eq = function(a, b)
	return a.x == b.x and a.y == b.y and a.z == b.z
end

function vectorMeta:Length()
	return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2)
end

function vectorMeta:Dot()
	return 0
end

function vectorMeta:Cross()
	return self
end

function vectorMeta:GetNormalized()
	return self
end

function env.Vector(x, y, z)
	return setmetatable({x = x or 0, y = y or 0, z = z or 0}, vectorMeta)
end

function env.LerpVector(fraction, from, to)
	return env.Vector(
		from.x + (to.x - from.x) * fraction,
		from.y + (to.y - from.y) * fraction,
		from.z + (to.z - from.z) * fraction
	)
end

local angleMeta = {}
angleMeta.__index = angleMeta

angleMeta.__add = function(a, b)
	return env.Angle(a.p + b.p, a.y + b.y, a.r + b.r)
end

angleMeta.__sub = function(a, b)
	return env.Angle(a.p - b.p, a.y - b.y, a.r - b.r)
end

function angleMeta:Forward()
	return env.Vector(1, 0, 0)
end

function angleMeta:Right()
	return env.Vector(0, -1, 0)
end

function angleMeta:Up()
	return env.Vector(0, 0, 1)
end

function env.Angle(p, y, r)
	return setmetatable({p = p or 0, y = y or 0, r = r or 0}, angleMeta)
end

function env.LerpAngle(fraction, from, to)
	return env.Angle(
		from.p + (to.p - from.p) * fraction,
		from.y + (to.y - from.y) * fraction,
		from.r + (to.r - from.r) * fraction
	)
end

function env.Matrix()
	local matrix = {}

	function matrix:Scale() end
	function matrix:Translate() end
	function matrix:Get() return matrix end
	function matrix:GetInverse() return matrix end
	function matrix:Set() end

	return matrix
end

function env.ProjectedTexture()
	return {
		SetEnableShadows = function() end,
		SetNearZ = function() end,
		SetFarZ = function() end,
		SetFOV = function() end,
		SetColor = function() end,
		SetTexture = function() end,
		SetBrightness = function() end,
		SetPos = function() end,
		SetAngles = function() end,
		Update = function() end,
		Remove = function() end
	}
end

function env.RunConsoleCommand()
end

function env.AddCSLuaFile()
end

-- =========================================================
-- surface / draw / render / cam — только запись вызовов
-- =========================================================

local drawLog = {}

env.__drawLog = drawLog

local surface = {}

local surfaceNoOp = {
	"SetDrawColor", "DrawRect", "DrawLine", "DrawTexturedRect", "DrawTexturedRectUV",
	"DrawTexturedRectRotated", "SetMaterial", "SetFont", "SetTextColor",
	"SetTextPos", "DrawText", "PlaySound", "GetTextureID", "CreateFont",
	"SetAlphaMultiplier", "DisableClipping", "SetScissorRect"
}

for _, name in ipairs(surfaceNoOp) do
	surface[name] = function() end
end

-- surface.DrawPoly в настоящем GMod рисует ТЕКСТУРИРУЕМЫЙ полигон текущей
-- текстурой. Если в момент вызова привязана текстура (например, осталась после
-- draw.RoundedBox), полигон семплит один её тексель и на экране невидим —
-- именно так выглядела «пустая» иконка в игре. Модель повторяет это: полигон
-- считается нарисованным, только когда текстура сброшена (draw.NoTexture или
-- surface.SetTexture() без аргумента).
local boundTexture = 0

function surface.SetTexture(id)
	boundTexture = id or 0
end

function surface.DrawPoly(vertices)
	drawLog[#drawLog + 1] = {type = "Poly", vertices = vertices, drawn = boundTexture == 0}
end

function surface.GetTextSize(text)
	return #(tostring(text)) * 6, 14
end

env.surface = surface

local draw = {}

function draw.RoundedBox(corner, x, y, w, h, color)
	drawLog[#drawLog + 1] = {type = "RoundedBox", x = x, y = y, w = w, h = h, color = color}

	-- Как в настоящем GMod: после RoundedBox привязана текстура скругления, и
	-- последующие DrawPoly без сброса текстуры были бы невидимы.
	boundTexture = 1001
end

function draw.RoundedBoxEx(corner, x, y, w, h, color)
	draw.RoundedBox(corner, x, y, w, h, color)
end

function draw.SimpleText(text, font, x, y, color, alignX, alignY)
	drawLog[#drawLog + 1] = {type = "Text", text = text, x = x, y = y, color = color}

	return surface.GetTextSize(text)
end

function draw.NoTexture()
	boundTexture = 0
end

function draw.GetFontHeight()
	return 14
end

env.draw = draw

env.render = {
	SetScissorRect = function() end,
	ClearStencil = function() end,
	SetStencilEnable = function() end,
	SetStencilFailOperation = function() end,
	SetStencilCompareFunction = function() end,
	SetStencilPassOperation = function() end,
	SetStencilReferenceValue = function() end,
	SetStencilWriteMask = function() end,
	SetStencilTestMask = function() end,
	SetBlend = function() end,
	SetColorModulation = function() end,
	SetMaterial = function() end,
	DrawScreenQuad = function() end,
	UpdateScreenEffectTexture = function() end,
	GetScreenEffectTexture = function() return 0 end,
	SetRenderTarget = function() end,
	PushRenderTarget = function() end,
	PopRenderTarget = function() end
}

env.cam = {
	PushModelMatrix = function() end,
	PopModelMatrix = function() end,
	Start2D = function() end,
	End2D = function() end
}

env.input = {
	IsMouseDown = function(code)
		return mouseDown[code] == true
	end,

	IsKeyDown = function(code)
		return keyDown[code] == true
	end,

	GetCursorPos = function()
		return cursorX, cursorY
	end
}

env.gui = {
	EnableScreenClicker = function(state)
		screenClicker = state
	end,

	IsGameUIVisible = function()
		return env.__gameUIVisible == true
	end,

	HideGameUI = function()
		env.__gameUIVisible = false
	end,

	OpenURL = function() end,

	SetMousePos = function(x, y)
		setCursor(x, y)
	end,

	InternalCursorMoved = function() end
}

env.__screenClicker = function()
	return screenClicker
end

env.__keyDown = function(code, state)
	keyDown[code] = state
end

env.__mouseDown = function(code, state)
	mouseDown[code] = state
end

-- =========================================================
-- cookie
-- =========================================================

env.cookie = {
	Set = function(key, value)
		env.__state.cookies[key] = tostring(value)
	end,

	GetString = function(key, default)
		local value = env.__state.cookies[key]

		return value == nil and (default or "") or value
	end,

	GetNumber = function(key, default)
		return tonumber(env.__state.cookies[key]) or default or 0
	end,

	Delete = function(key)
		env.__state.cookies[key] = nil
	end
}

-- =========================================================
-- hook
-- =========================================================

local hooks = {}

env.__hooks = hooks

env.hook = {}

function env.hook.Add(name, identifier, func)
	hooks[name] = hooks[name] or {}
	hooks[name][identifier] = func
end

function env.hook.Remove(name, identifier)
	if (hooks[name]) then
		hooks[name][identifier] = nil
	end
end

function env.hook.Run(name, ...)
	if (hooks[name]) then
		for _, func in pairs(hooks[name]) do
			local results = {func(...)}

			if (#results > 0) then
				return unpack(results)
			end
		end
	end

	-- В движке hook.Run всегда доходит до метода гейммода — на этом держится
	-- GM:ScoreboardShow (создание ixMenu) и GM:CharacterLoaded (закрытие меню).
	if (env.GM and env.GM[name]) then
		return env.GM[name](env.GM, ...)
	end
end

env.hook.Call = env.hook.Run

-- =========================================================
-- timer
-- =========================================================

env.timer = {}

local timerIndex = 0

local function createTimer(name, delay, repetitions, func)
	timerIndex = timerIndex + 1

	timers[name] = {
		name = name,
		delay = math.max(delay or 0, 0),
		repetitions = repetitions or 1,
		nextRun = clock.time + math.max(delay or 0, 0),
		func = func
	}
end

function env.timer.Create(name, delay, repetitions, func)
	createTimer(name, delay, repetitions, func)
end

function env.timer.Simple(delay, func)
	timerIndex = timerIndex + 1
	createTimer("__simple" .. timerIndex, delay, 1, func)
end

function env.timer.Remove(name)
	timers[name] = nil
end

function env.timer.Adjust(name, delay, repetitions, func)
	createTimer(name, delay, repetitions, func)
end

function env.timer.Exists(name)
	return timers[name] ~= nil
end

local function runTimers()
	local due = {}

	for name, entry in pairs(timers) do
		if (clock.time >= entry.nextRun) then
			due[#due + 1] = entry
		end
	end

	table.sort(due, function(a, b)
		return a.nextRun < b.nextRun
	end)

	for _, entry in ipairs(due) do
		if (timers[entry.name] == entry) then
			if (entry.repetitions != 0) then
				entry.repetitions = entry.repetitions - 1
			end

			entry.nextRun = clock.time + entry.delay

			if (entry.repetitions == 0) then
				timers[entry.name] = nil
			end

			entry.func()
		end
	end
end

-- =========================================================
-- звук
-- =========================================================

env.GMOD_CHANNEL_STOPPED = 0
env.GMOD_CHANNEL_PLAYING = 1
env.GMOD_CHANNEL_PAUSED = 2

local channelMeta = {}
channelMeta.__index = channelMeta

local channelIndex = 0

function channelMeta:Play()
	-- Возобновление учитывает текущий курсор (в т.ч. после SetTime на паузе).
	self.startTime = clock.time - self.time
	self.state = env.GMOD_CHANNEL_PLAYING
end

function channelMeta:Stop()
	self.state = env.GMOD_CHANNEL_STOPPED
	self.time = 0
end

function channelMeta:Pause()
	if (self.state == env.GMOD_CHANNEL_PLAYING) then
		self.time = self:GetTime()
		self.state = env.GMOD_CHANNEL_PAUSED
	end
end

function channelMeta:GetState()
	return self.state
end

function channelMeta:IsPlaying()
	return self.state == env.GMOD_CHANNEL_PLAYING
end

function channelMeta:SetVolume(volume)
	self.volume = volume
end

function channelMeta:GetVolume()
	return self.volume
end

function channelMeta:GetPlaybackRate()
	return 1
end

function channelMeta:GetLength()
	return self.length
end

function channelMeta:GetTime()
	if (self.state == env.GMOD_CHANNEL_PLAYING) then
		return clock.time - self.startTime
	end

	return self.time
end

function channelMeta:SetTime(time)
	self.time = time

	if (self.state == env.GMOD_CHANNEL_PLAYING) then
		self.startTime = clock.time - time
	end
end

function channelMeta:SetPlaybackRate()
end

function channelMeta:Set3DFadeDistance()
end

env.__channelMeta = channelMeta

env.sound = {}

function env.sound.PlayFile(path, flags, callback)
	channelIndex = channelIndex + 1

	local channel = setmetatable({
		__isValid = true,
		id = channelIndex,
		path = path,
		flags = flags,
		state = env.GMOD_CHANNEL_STOPPED,
		volume = 1,
		time = 0,
		startTime = 0,
		length = 187.4
	}, channelMeta)

	env.__state.channels[#env.__state.channels + 1] = channel

	-- Загрузка асинхронная, как в движке: ответ приходит следующим кадром.
	env.timer.Simple(0.02, function()
		callback(channel, 0, "")
	end)

	return channel
end

function env.sound.PlayURL(url, flags, callback)
	return env.sound.PlayFile(url, flags, callback)
end

function env.sound.Play()
end

function env.sound.Add()
end

-- =========================================================
-- VGUI
-- =========================================================

local classes = {}
local rootPanels = {}

env.__classes = classes
env.__rootPanels = rootPanels

local Panel = {}
Panel.__index = Panel
Panel.ClassName = "Panel"

-- accessors
function Panel:SetPos(x, y)
	self.x, self.y = x or 0, y or 0
end

function Panel:GetPos()
	return self.x, self.y
end

function Panel:SetX(x)
	self.x = x
end

function Panel:GetX()
	return self.x
end

function Panel:SetY(y)
	self.y = y
end

function Panel:GetY()
	return self.y
end

function Panel:SetSize(w, h)
	self.w, self.h = w or 0, h or 0
end

function Panel:SetWide(w)
	self.w = w
end

function Panel:SetTall(h)
	self.h = h
end

function Panel:GetSize()
	return self.w, self.h
end

function Panel:GetWide()
	return self.w
end

function Panel:GetTall()
	return self.h
end

function Panel:SetVisible(state)
	self.m_bVisible = state and true or false
end

function Panel:Show()
	self:SetVisible(true)
end

function Panel:Hide()
	self:SetVisible(false)
end

function Panel:IsVisible()
	local current = self

	while (current) do
		if (!current.m_bVisible) then
			return false
		end

		current = current.m_pParent
	end

	return true
end

function Panel:SetAlpha(alpha)
	self.m_iAlpha = alpha
end

function Panel:GetAlpha()
	return self.m_iAlpha == nil and 255 or self.m_iAlpha
end

function Panel:AlphaTo(alpha, duration, delay, callback)
	delay = delay or 0
	duration = duration or 0

	alphaAnims[#alphaAnims + 1] = {
		panel = self,
		from = self:GetAlpha(),
		to = alpha,
		start = clock.time + delay,
		duration = duration,
		callback = callback
	}
end

function Panel:SetZPos(z)
	self.m_iZPos = z
end

function Panel:GetZPos()
	return self.m_iZPos or 0
end

function Panel:SetParent(parent)
	if (self.m_pParent) then
		local children = self.m_pParent.m_children

		for i, child in ipairs(children) do
			if (child == self) then
				table.remove(children, i)

				break
			end
		end
	end

	self.m_pParent = parent

	if (parent) then
		parent.m_children[#parent.m_children + 1] = self

		for i, root in ipairs(rootPanels) do
			if (root == self) then
				table.remove(rootPanels, i)

				break
			end
		end
	elseif (self.__isValid) then
		rootPanels[#rootPanels + 1] = self
	end
end

function Panel:GetParent()
	return self.m_pParent
end

function Panel:GetChildren()
	return self.m_children
end

function Panel:Add(name)
	return env.vgui.Create(name, self)
end

function Panel:Remove()
	if (self.__isValid != true) then
		return
	end

	self.__isValid = false

	local children = {}

	for _, child in ipairs(self.m_children) do
		children[#children + 1] = child
	end

	for _, child in ipairs(children) do
		child:Remove()
	end

	self.m_children = {}

	if (self.OnRemove) then
		self:OnRemove()
	end

	if (self.m_pParent) then
		local children = self.m_pParent.m_children

		for i, child in ipairs(children) do
			if (child == self) then
				table.remove(children, i)

				break
			end
		end

		self.m_pParent = nil
	else
		for i, root in ipairs(rootPanels) do
			if (root == self) then
				table.remove(rootPanels, i)

				break
			end
		end
	end

	for i, panel in ipairs(panelList) do
		if (panel == self) then
			table.remove(panelList, i)

			break
		end
	end
end

function Panel:SetMouseInputEnabled(state)
	self.m_bMouseInputEnabled = state and true or false
end

function Panel:IsMouseInputEnabled()
	return self.m_bMouseInputEnabled == true
end

function Panel:SetKeyboardInputEnabled(state)
	self.m_bKeyboardInputEnabled = state and true or false
end

function Panel:MakePopup()
	self:SetMouseInputEnabled(true)
	self:SetKeyboardInputEnabled(true)
	env.gui.EnableScreenClicker(true)
end

function Panel:SetCursor(name)
	self.m_cursor = name
end

function Panel:SetTooltip(text)
	self.m_tooltip = text
end

function Panel:SetToolTip(text)
	self:SetTooltip(text)
end

function Panel:MoveToFront()
	local parent = self.m_pParent

	if (!parent) then
		for i, root in ipairs(rootPanels) do
			if (root == self) then
				table.remove(rootPanels, i)
				rootPanels[#rootPanels + 1] = self

				break
			end
		end

		return
	end

	local children = parent.m_children

	for i, child in ipairs(children) do
		if (child == self) then
			table.remove(children, i)
			children[#children + 1] = self

			break
		end
	end
end

function Panel:MoveToBefore(other)
	local parent = self.m_pParent

	if (!parent) then
		return
	end

	local children = parent.m_children
	local selfIndex, otherIndex

	for i, child in ipairs(children) do
		if (child == self) then
			selfIndex = i
		elseif (child == other) then
			otherIndex = i
		end
	end

	if (selfIndex and otherIndex and selfIndex > otherIndex) then
		table.remove(children, selfIndex)
		table.insert(children, otherIndex, self)
	end
end

function Panel:RequestFocus()
end

function Panel:MouseCapture(state)
	self.m_bMouseCaptured = state and true or false
end

function Panel:LocalToScreen(x, y)
	local parent = self.m_pParent
	local offsetX, offsetY = self.x, self.y

	while (parent) do
		offsetX = offsetX + parent.x
		offsetY = offsetY + parent.y
		parent = parent.m_pParent
	end

	return offsetX + (x or 0), offsetY + (y or 0)
end

function Panel:ScreenToLocal(x, y)
	local screenX, screenY = self:LocalToScreen(0, 0)

	return x - screenX, y - screenY
end

function Panel:CursorPos()
	local screenX, screenY = self:LocalToScreen(0, 0)

	return cursorX - screenX, cursorY - screenY
end

function Panel:IsHovered()
	if (!self:IsVisible()) then
		return false
	end

	local screenX, screenY = self:LocalToScreen(0, 0)

	return cursorX >= screenX and cursorX <= screenX + self.w
		and cursorY >= screenY and cursorY <= screenY + self.h
end

function Panel:SetPaintedManually(state)
	self.m_bPaintedManually = state and true or false
end

function Panel:GetPaintedManually()
	return self.m_bPaintedManually == true
end

function Panel:PaintManual()
end

function Panel:InvalidateLayout()
end

function Panel:Dock(mode)
	self.m_dock = mode
end

function Panel:GetDock()
	return self.m_dock or 0
end

function Panel:DockMargin()
end

function Panel:DockPadding(left, top, right, bottom)
	self.m_dockPadding = {left, top, right, bottom}
end

function Panel:GetPadding()
	return (self.m_dockPadding and self.m_dockPadding[1]) or 0
end

function Panel:Center()
	local parent = self.m_pParent

	if (!parent) then
		return
	end

	self:SetPos((parent:GetWide() - self.w) * 0.5, (parent:GetTall() - self.h) * 0.5)
end

function Panel:SetTitle()
end

function Panel:ShowCloseButton()
end

function Panel:SetDraggable()
end

function Panel:SetSizable()
end

function Panel:SetDeleteOnClose()
end

function Panel:SlideDown()
end

function Panel:SlideUp()
end

function Panel:Slide()
end

function Panel:SetEnabled(state)
	self.m_bEnabled = state and true or false
end

function Panel:GetEnabled()
	return self.m_bEnabled ~= false
end

function Panel:IsEnabled()
	return self:GetEnabled()
end

function Panel:SetDisabled(state)
	self:SetEnabled(not state)
end

function Panel:GetDisabled()
	return not self:GetEnabled()
end

function Panel:IsDown()
	return self.m_bDown == true
end

function Panel:SetText(text)
	self.m_text = tostring(text)
end

function Panel:GetText()
	return self.m_text
end

function Panel:SetFont()
end

function Panel:SetTextColor(color)
	self.m_textColor = color
end

function Panel:GetTextColor()
	return self.m_textColor or env.color_white
end

function Panel:SetFGColor(color)
	self.m_fgColor = color
end

function Panel:SetPaintBackground()
end

function Panel:SetContentAlignment()
end

function Panel:SetTextInset()
end

function Panel:SizeToContents()
	self.w = #(self.m_text or "") * 7 + 8
	self.h = 20
end

function Panel:SizeToContentsY()
	self.h = 20
end

function Panel:SizeToContentsX()
	self.w = #(self.m_text or "") * 7 + 8
end

function Panel:SetMaterial()
end

function Panel:MoveBelow()
end

function Panel:MoveLeftOf()
end

function Panel:MoveRightOf()
end

function Panel:SetAnimationEnabled()
end

function Panel:ParentToHUD()
end

function Panel:GetVBar()
	self.m_vbar = self.m_vbar or env.vgui.Create("Panel", self)

	return self.m_vbar
end

function Panel:GetCanvas()
	self.m_canvas = self.m_canvas or env.vgui.Create("Panel", self)

	return self.m_canvas
end

function Panel:GetScroll()
	return 0
end

-- базовые обработчики ввода
function Panel:OnMousePressed()
end

function Panel:OnMouseReleased()
end

function Panel:OnCursorMoved()
end

function Panel:OnCursorEntered()
end

function Panel:OnCursorExited()
end

function Panel:OnMouseWheeled()
end

function Panel:OnKeyCodePressed()
end

function Panel:PerformLayout()
end

function Panel:Paint()
end

function Panel:Think()
end

function Panel:GetTable()
	return self
end

function Panel:Prepare()
end

Panel.Base = nil
classes.Panel = Panel
env.__Panel = Panel

function env.FindMetaTable(name)
	if (name == "Panel") then
		return Panel
	end

	return nil
end

-- =========================================================
-- vgui / derma
-- =========================================================

env.vgui = {}

-- Реализация повторяет garrysmod/lua/includes/extensions/client/panel/
-- scriptedpanels.lua: vgui.Create сначала создаёт базовую панель, затем
-- подмешивает таблицу класса и вызывает Init на КАЖДОМ уровне наследования.
-- Именно поэтому ixSubpanelParent:Init успевает задать padding до того, как
-- ixCharMenuMain:Init его использует.

function env.table.Merge(tTo, tFrom)
	for key, value in pairs(tFrom) do
		if (type(value) == "table") then
			if (type(tTo[key]) ~= "table") then
				tTo[key] = {}
			end

			env.table.Merge(tTo[key], value)
		else
			tTo[key] = value
		end
	end

	return tTo
end

function env.vgui.Register(classname, mtable, base)
	env.PANEL = nil

	mtable = mtable or {}
	mtable.Base = base or "Panel"
	mtable.Init = mtable.Init or function() end

	classes[classname] = mtable

	local mt = {}

	mt.__index = function(_, key)
		local baseTable = classes[mtable.Base]

		if (baseTable and baseTable[key] != nil) then
			return baseTable[key]
		end

		return Panel[key]
	end

	setmetatable(mtable, mt)

	return mtable
end

function env.vgui.RegisterTable(mtable, base)
	env.PANEL = nil

	mtable.Base = base or "Panel"
	mtable.Init = mtable.Init or function() end

	return mtable
end

function env.vgui.GetControlTable(classname)
	return classes[classname]
end

function env.vgui.Exists(classname)
	return classes[classname] != nil
end

function env.vgui.Create(classname, parent, name)
	local class = classes[classname]

	if (class and class.Base) then
		local panel = env.vgui.Create(class.Base, parent, name or classname)

		env.table.Merge(panel, class)
		panel.BaseClass = classes[class.Base]
		panel.ClassName = classname

		if (panel.Init) then
			panel:Init()
		end

		panel:Prepare()

		return panel
	end

	local instance = setmetatable({
		__isValid = true,
		m_children = {},
		m_bVisible = true,
		m_iAlpha = 255,
		x = 0,
		y = 0,
		w = 0,
		h = 0,
		m_iZPos = 0
	}, {__index = Panel})

	instance.ClassName = classname or "Panel"

	panelList[#panelList + 1] = instance

	if (parent) then
		instance:SetParent(parent)
	else
		rootPanels[#rootPanels + 1] = instance
	end

	if (instance.Init) then
		instance:Init()
	end

	return instance
end

function env.vgui.CreateFromTable(mtable, parent, name)
	return env.vgui.Create(mtable.ClassName or "Panel", parent, name)
end

function env.vgui.CursorVisible()
	return screenClicker
end

local derma = {}

function derma.SkinFunc(name, ...)
	if (env.__skinFuncs and env.__skinFuncs[name]) then
		return env.__skinFuncs[name](...)
	end
end

function derma.DefineSkin()
end

function derma.GetNamedSkin()
	return {}
end

function derma.Color()
	return env.color_white
end

function derma.GetColor(name, panel)
	if (panel and panel.m_textColor) then
		return panel.m_textColor
	end

	return env.color_white
end

function derma.SkinHook()
end

env.derma = derma

env.__skinFuncs = {}

-- =========================================================
-- AccessorFunc / DEFINE_BASECLASS
-- =========================================================

env.FORCE_NUMBER = 1
env.FORCE_BOOL = 2
env.FORCE_STRING = 3

function env.AccessorFunc(table_, member, name, forceType)
	table_["Get" .. name] = function(self)
		return self[member]
	end

	table_["Set" .. name] = function(self, value)
		if (forceType == env.FORCE_NUMBER) then
			value = tonumber(value) or 0
		elseif (forceType == env.FORCE_BOOL) then
			value = value and true or false
		elseif (forceType == env.FORCE_STRING) then
			value = tostring(value)
		end

		self[member] = value

		if (self["On" .. name .. "Changed"]) then
			self["On" .. name .. "Changed"](self, self[member])
		end
	end
end

function env.DEFINE_BASECLASS(name)
	local base = classes[name] or Panel
	env.BaseClass = base
	env["base_" .. name] = base
end

-- =========================================================
-- константы
-- =========================================================

env.MOUSE_LEFT = 107
env.MOUSE_RIGHT = 108
env.MOUSE_MIDDLE = 109

env.KEY_TAB = 38
env.KEY_ESCAPE = 63
env.KEY_SPACE = 65
env.KEY_ENTER = 40

env.TOP = 1
env.BOTTOM = 2
env.LEFT = 3
env.RIGHT = 4
env.FILL = 5
env.NODOCK = 0

env.TEXT_ALIGN_LEFT = 0
env.TEXT_ALIGN_CENTER = 1
env.TEXT_ALIGN_RIGHT = 2
env.TEXT_ALIGN_TOP = 3
env.TEXT_ALIGN_BOTTOM = 4

env.color_white = env.Color(255, 255, 255, 255)
env.color_black = env.Color(0, 0, 0, 255)
env.color_transparent = env.Color(0, 0, 0, 0)

env.GMOD_CHANNEL_STOPPED = 0

env.FCVAR_ARCHIVE = 128
env.FCVAR_USERINFO = 512
env.FCVAR_DONTRECORD = 8192

env.ConVar = {}

function env.CreateConVar()
	return {}
end

function env.GetConVar()
	return nil
end

-- =========================================================
-- игрок / concommand / net / resource
-- =========================================================

local player = {
	__isValid = true,
	character = nil,

	GetCharacter = function(self)
		return self.character
	end,

	EmitSound = function() end,
	Team = function() return 1 end,
	GetPos = function() return env.Vector() end,
	GetForward = function() return env.Vector(1, 0, 0) end,
	GetRight = function() return env.Vector(0, -1, 0) end,
	GetAngles = function() return env.Angle() end,
	OBBCenter = function() return env.Vector() end,
	Name = function() return "Player" end,
	SteamID64 = function() return "0" end,
	IsAdmin = function() return false end,
	IsValid = function() return true end
}

env.__player = player

function env.LocalPlayer()
	return player
end

function env.Entity()
	return nil
end

local concommands = {}

env.__concommands = concommands

env.concommand = {}

function env.concommand.Add(name, func)
	concommands[name] = func
end

function env.concommand.Remove(name)
	concommands[name] = nil
end

env.net = {
	Start = function() end,
	WriteUInt = function() end,
	WriteBool = function() end,
	WriteString = function() end,
	WriteEntity = function() end,
	SendToServer = function() end,
	Receive = function(name, func)
		env.__netReceivers[name] = func
	end,

	ReadUInt = function()
		return table.remove(env.__netQueue, 1) or 0
	end,

	ReadBool = function() return false end,
	ReadString = function() return "" end
}

env.__netReceivers = {}
env.__netQueue = {}

function env.__net(name, ...)
	env.__netQueue = {...}

	local receiver = env.__netReceivers[name]

	if (!receiver) then
		error("нет net.Receive для " .. tostring(name))
	end

	receiver()
end

env.resource = {
	AddFile = function() end,
	AddSingleFile = function() end
}

env.util = env.util or {}

function env.util.Path(fileName)
	return fileName
end

-- =========================================================
-- include (относительно файла-источника, как в движке)
-- =========================================================

local loadedChunks = {}

function env.__loadGLua(path)
	if (loadedChunks[path]) then
		return loadedChunks[path]
	end

	local handle = assert(io.open(path, "rb"))
	local source = handle:read("*a")
	handle:close()

	local chunk = assert(loadstring(translate(source), "@" .. path))
	setfenv(chunk, env)

	loadedChunks[path] = true

	return chunk()
end

function env.include(fileName)
	local currentFile = debug.getinfo(2, "S").source:match("^@(.*[/\\])") or "./"

	return env.__loadGLua(currentFile .. fileName)
end

-- =========================================================
-- покадровый насос
-- =========================================================

local function runAlphaAnims()
	for i = #alphaAnims, 1, -1 do
		local entry = alphaAnims[i]

		if (clock.time >= entry.start) then
			local fraction = entry.duration > 0 and math.min((clock.time - entry.start) / entry.duration, 1) or 1
			entry.panel:SetAlpha(entry.from + (entry.to - entry.from) * fraction)

			if (fraction >= 1) then
				table.remove(alphaAnims, i)

				if (entry.callback) then
					entry.callback()
				end
			end
		end
	end
end

local function walkPanels(callback)
	local function visit(panel)
		if (!panel.__isValid or !panel.m_bVisible) then
			return
		end

		callback(panel)

		-- дети рисуются и думают в порядке добавления, как в VGUI
		for _, child in ipairs(panel.m_children) do
			visit(child)
		end
	end

	for _, root in ipairs(rootPanels) do
		visit(root)
	end
end

function env.__thinkPanels()
	walkPanels(function(panel)
		if (panel.AnimationThink) then
			panel:AnimationThink()
		end

		if (panel.Think and panel.__isValid) then
			panel:Think()
		end
	end)
end

function env.__paintPanels()
	drawLog = {}
	env.__drawLog = drawLog

	walkPanels(function(panel)
		if (!panel.m_bPaintedManually and panel.Paint) then
			panel:Paint(panel.w, panel.h)
		end
	end)
end

function env.__frame(dt)
	dt = dt or clock.frameTime
	clock.frameTime = dt
	clock.time = clock.time + dt
	clock.real = clock.real + dt

	runTimers()

	for _, channel in ipairs(env.__state.channels) do
		if (channel.state == env.GMOD_CHANNEL_PLAYING and channel:GetTime() >= channel.length) then
			channel.state = env.GMOD_CHANNEL_STOPPED
		end
	end

	env.hook.Run("Think")
	env.__thinkPanels()
	runAlphaAnims()
	env.__paintPanels()
end

-- Прогон времени: seconds — длительность, step — длина кадра.
function env.__advance(seconds, step)
	step = step or 1 / 60
	local frames = math.max(1, math.floor((seconds / step) + 0.5))

	for _ = 1, frames do
		env.__frame(step)
	end
end

return env
