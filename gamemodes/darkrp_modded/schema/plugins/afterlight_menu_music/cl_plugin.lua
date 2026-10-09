if (!CLIENT) then return end

--[[
	Afterlight Music — единый музыкальный контроллер проекта.

	Контроллер — единственный владелец звукового канала. Заставка, меню
	персонажей и игровое меню Helix (TAB) не создают собственных каналов, а
	сообщают контроллеру, что им нужен звук, через SetContext(). Громкость
	одна на все экраны и хранится в cookie, поэтому она переживает переходы
	между экранами и переподключение.

	Интеграция сверена с исходниками Helix (NebulousCloud/helix, master):
	  * gamemode/core/derma/cl_character.lua — ixCharMenu пишет себя в
	    ix.gui.characterMenu, а Close() ставит self.bClosing и гасит панель
	    примерно 4 секунды, поэтому признаком «меню открыто» служит !bClosing.
	  * gamemode/core/derma/cl_menu.lua — ixMenu пишет себя в ix.gui.menu,
	    его Remove() тоже переопределён и убирает панель не сразу, а после
	    анимации на animationTime * 0.5.
	  * gamemode/core/hooks/cl_hooks.lua — GM:ScoreboardShow только создаёт
	    ixMenu, а GM:ScoreboardHide пуст, поэтому состояние читается по панели,
	    а не по хуку. Игровое меню Helix закрывается само в PANEL:Think.
	  * ix.gui.mainMenu и ix.gui.tabMenu в Helix не существуют.
	  * hook OnCharacterDisconnect объявлен только на сервере
	    (gamemode/core/hooks/sv_hooks.lua), на клиенте его нет.
	  * Сигнал выбора персонажа на клиенте — hook CharacterLoaded
	    (gamemode/core/libs/sh_character.lua, net.Receive("ixCharacterLoaded")).
	  * Меню персонажей и заставка Helix заводят собственные каналы
	    (self.channel), поэтому контроллер глушит их и остаётся один источник.

	Громкость одна на все экраны и меняется полосой из cl_volume.lua; сама
	полоса скрыта и вызывается кликом по иконке динамика в правом нижнем углу
	экрана (cl_volume_button.lua).
]]

-- Сохраняем канал и громкость при lua_refresh, чтобы трек не перезапускался.
local previous = AfterlightMusic

AfterlightMusic = {}

local MUSIC = AfterlightMusic

-- =========================================================
-- НАСТРОЙКИ
-- =========================================================

MUSIC.soundPath = "sound/afterlight/intro_music.mp3"
MUSIC.cookieKey = "afterlight_music_volume"
MUSIC.defaultVolume = 0.75

-- Длительность плавного появления и затухания, секунды.
MUSIC.fadeInTime = 2.5
MUSIC.fadeOutTime = 3

-- Сколько секунд удерживать звук после закрытия последнего экрана: этого
-- хватает, чтобы Helix успел открыть следующее меню без разрыва трека.
MUSIC.holdTime = 1

-- Запас до конца трека, на котором начинается новый круг.
MUSIC.loopThreshold = 0.3

-- Пауза перед записью cookie, чтобы не писать её каждый кадр жеста.
MUSIC.volumeSaveDelay = 0.4

-- Глушить ли собственную музыку Helix (меню персонажей, заставка Helix).
MUSIC.bSilenceHelixMusic = true

-- Имена контекстов. Контекст — это просьба «мне сейчас нужна музыка».
MUSIC.CONTEXT_INTRO = "intro"
MUSIC.CONTEXT_CHARACTER_MENU = "characterMenu"
MUSIC.CONTEXT_MENU = "menu"

MUSIC.hookName = "AfterlightMusicController"

-- Панели Helix, у которых бывает собственный канал self.channel.
MUSIC.helixMusicPanels = {"characterMenu", "intro"}

-- =========================================================
-- СОСТОЯНИЕ
-- =========================================================

MUSIC.channel = (previous and IsValid(previous.channel)) and previous.channel or nil
MUSIC.channelGeneration = (previous and previous.channelGeneration or 0) + 1
MUSIC.contexts = (previous and previous.contexts) or {}

local function ReadVolume()
	local value = tonumber(cookie.GetString(MUSIC.cookieKey, ""))

	if (!value) then
		value = MUSIC.defaultVolume
	end

	return math.Clamp(value, 0, 1)
end

if (previous and previous.volume) then
	MUSIC.volume = previous.volume
else
	MUSIC.volume = ReadVolume()
end

MUSIC.envelope = (previous and previous.envelope) or 0
MUSIC.bWanted = false
MUSIC.isLoading = false
-- Окно удержания не должно срабатывать само по себе при загрузке.
MUSIC.lastActiveTime = CurTime() - MUSIC.holdTime - 1
MUSIC.lastAppliedVolume = nil
MUSIC.bVolumeDirty = false
MUSIC.volumeSaveTime = nil
MUSIC.silencedChannels = setmetatable({}, {__mode = "k"})

-- =========================================================
-- ОЧИСТКА ЗА ПРЕДЫДУЩЕЙ ВЕРСИЕЙ ФАЙЛА (LUA_REFRESH)
-- =========================================================

timer.Remove("AfterlightMusicController")
timer.Remove("AfterlightMusicFadeOut")
timer.Remove("AfterlightMusicStateSanityCheck")

hook.Remove("Think", "AfterlightMusicCharacterMenuWatcher")
hook.Remove("Think", "AfterlightMusicVolumeMenus")
hook.Remove("ScoreboardShow", "AfterlightMusicScoreboardShow")
hook.Remove("ScoreboardHide", "AfterlightMusicScoreboardHide")
hook.Remove("CharacterLoaded", "AfterlightMusicCharacterLoaded")
hook.Remove("OnCharacterDisconnect", "AfterlightMusicCharacterDisconnect")

concommand.Remove("afterlight_music_play")
concommand.Remove("afterlight_music_stop")
concommand.Remove("afterlight_music_fade")
concommand.Remove("afterlight_music_status")
concommand.Remove("afterlight_music_volume")
concommand.Remove("afterlight_music_bar")

-- =========================================================
-- ГРОМКОСТЬ
-- =========================================================

function MUSIC:GetVolume()
	return self.volume
end

function MUSIC:GetEffectiveVolume()
	return self.volume * self.envelope
end

-- bTransient — жест ещё продолжается: значение применяется сразу, но cookie
-- записывается с задержкой (см. UpdateVolumeSaving) либо в конце жеста.
function MUSIC:SetVolume(volume, bTransient)
	local value = tonumber(volume)

	if (!value) then
		return self.volume
	end

	self.volume = math.Clamp(value, 0, 1)
	self:ApplyVolume()

	if (bTransient) then
		self.bVolumeDirty = true
		self.volumeSaveTime = CurTime() + self.volumeSaveDelay
	else
		self:SaveVolume()
	end

	return self.volume
end

function MUSIC:SaveVolume()
	self.bVolumeDirty = false
	self.volumeSaveTime = nil

	cookie.Set(self.cookieKey, tostring(self.volume))
end

function MUSIC:UpdateVolumeSaving()
	if (self.bVolumeDirty and CurTime() >= (self.volumeSaveTime or 0)) then
		self:SaveVolume()
	end
end

function MUSIC:ApplyVolume()
	if (!IsValid(self.channel)) then
		self.lastAppliedVolume = nil

		return
	end

	local volume = self.volume * self.envelope

	if (self.lastAppliedVolume and math.abs(self.lastAppliedVolume - volume) < 0.0005) then
		return
	end

	self.lastAppliedVolume = volume
	self.channel:SetVolume(volume)
end

-- =========================================================
-- КОНТЕКСТЫ (ЕДИНСТВЕННЫЙ ПУБЛИЧНЫЙ ВХОД ДЛЯ ДРУГИХ ПЛАГИНОВ)
-- =========================================================

function MUSIC:SetContext(name, bActive, bSilent)
	if (!name) then
		return
	end

	if (bActive) then
		self.contexts[name] = true
	else
		self.contexts[name] = nil
	end

	if (!bSilent) then
		self:Update()
	end
end

function MUSIC:IsContextActive(name)
	return self.contexts[name] == true
end

function MUSIC:ClearContexts()
	self.contexts = {}
	self.lastActiveTime = CurTime() - self.holdTime - 1
end

-- Контексты меню персонажей и игрового меню выводятся из реального состояния
-- панелей Helix каждый кадр, поэтому порядок загрузки плагинов не важен.
function MUSIC:SyncContexts()
	self:SetContext(self.CONTEXT_CHARACTER_MENU, self:IsCharacterMenuOpen(), true)
	self:SetContext(self.CONTEXT_MENU, self:IsMenuOpen(), true)
end

-- Интро само снимает свой контекст; это страховка на случай, если файл
-- заставки упал с ошибкой посреди закрытия.
function MUSIC:ValidateContexts()
	if (!self.contexts[self.CONTEXT_INTRO]) then
		return
	end

	local intro = AfterlightIntro

	if (!intro or (!intro.active and !intro.closing) or !IsValid(intro.frame)) then
		self:SetContext(self.CONTEXT_INTRO, false, true)
	end
end

-- =========================================================
-- СОСТОЯНИЕ ПАНЕЛЕЙ HELIX
-- =========================================================

function MUSIC:IsPanelOpen(panel)
	if (!IsValid(panel) or panel.bClosing) then
		return false
	end

	return panel:IsVisible() and panel:GetAlpha() > 0
end

function MUSIC:IsCharacterMenuOpen()
	return ix and ix.gui and self:IsPanelOpen(ix.gui.characterMenu) and true or false
end

function MUSIC:IsMenuOpen()
	return ix and ix.gui and self:IsPanelOpen(ix.gui.menu) and true or false
end

function MUSIC:GetChainAlpha(panel)
	local alpha = 1
	local current = panel

	while (IsValid(current)) do
		alpha = alpha * (current:GetAlpha() / 255)
		current = current:GetParent()
	end

	return alpha
end

-- =========================================================
-- РЕШЕНИЕ: НУЖЕН ЛИ ЗВУК
-- =========================================================

function MUSIC:Update()
	local bActive = false

	for _ in pairs(self.contexts) do
		bActive = true

		break
	end

	if (bActive) then
		self.lastActiveTime = CurTime()
	end

	-- Окно удержания перекрывает переходы «интро -> меню персонажей» и
	-- «TAB -> меню персонажей»: трек не останавливается и не стартует заново.
	self.bWanted = bActive or (CurTime() - self.lastActiveTime) < self.holdTime
end

-- =========================================================
-- КАНАЛ
-- =========================================================

function MUSIC:EnsureChannel()
	if (IsValid(self.channel) or self.isLoading or !self.bWanted) then
		return
	end

	self.isLoading = true

	local generation = self.channelGeneration
	local envelope = self.envelope

	sound.PlayFile(self.soundPath, "noplay", function(channel, errorID, errorName)
		self.isLoading = false

		if (!IsValid(channel)) then
			MsgN("[Afterlight Music] Не удалось загрузить ", self.soundPath, ": ",
				errorName or errorID or "неизвестная ошибка")

			return
		end

		-- Запрос устарел (Stop или lua_refresh) либо канал уже появился —
		-- лишний канал гасим сразу, наложения быть не должно.
		if (generation != self.channelGeneration or (IsValid(self.channel) and self.channel != channel)) then
			channel:Stop()

			return
		end

		self.channel = channel
		self.lastAppliedVolume = nil

		channel:SetVolume(self.volume * envelope)

		if (self.bWanted) then
			channel:Play()
		end
	end)
end

function MUSIC:Stop()
	self:ClearContexts()
	self.bWanted = false
	self.envelope = 0
	self.isLoading = false
	self.lastAppliedVolume = nil
	self.channelGeneration = self.channelGeneration + 1

	if (IsValid(self.channel)) then
		self.channel:Stop()
	end

	self.channel = nil
end

-- Мягкое завершение: снимаем все контексты, дальше работает огибающая.
function MUSIC:FadeOut()
	self:ClearContexts()
	self:Update()
end

-- Трек зацикливается вручную: sound.PlayFile не повторяет mp3 сам.
function MUSIC:LoopTrack()
	if (!IsValid(self.channel) or self.channel:GetState() != GMOD_CHANNEL_PLAYING) then
		return
	end

	local length = self.channel:GetLength()

	if (!length or length <= 0) then
		return
	end

	local time = self.channel:GetTime()

	if (time and time >= length - self.loopThreshold) then
		self.channel:SetTime(0)
	end
end

-- Огибающая даёт плавное появление и затухание; канал при этом не
-- пересоздаётся. Пока звук ещё не затух (переходы между экранами), трек
-- продолжается с того же места; после полного затухания он перематывается в
-- начало, и следующее открытие меню запускает музыку заново.
function MUSIC:UpdateEnvelope()
	local target = self.bWanted and 1 or 0

	if (self.envelope != target) then
		local duration = math.max(target > self.envelope and self.fadeInTime or self.fadeOutTime, 0.01)
		local delta = FrameTime() / duration

		if (target > self.envelope) then
			self.envelope = math.min(self.envelope + delta, 1)
		else
			self.envelope = math.max(self.envelope - delta, 0)
		end
	end

	self:ApplyVolume()
end

function MUSIC:UpdateChannel()
	if (!IsValid(self.channel)) then
		return
	end

	local state = self.channel:GetState()
	local bShouldSound = self.bWanted and self.envelope > 0

	if (bShouldSound and state != GMOD_CHANNEL_PLAYING) then
		self.channel:Play()
	elseif (!bShouldSound and self.envelope <= 0 and state == GMOD_CHANNEL_PLAYING) then
		self.channel:Pause()

		-- Музыка полностью затухла: следующий запуск идёт с начала трека.
		-- Переходы между экранами сюда не попадают — окно удержания не даёт
		-- огибающей дойти до нуля, и трек продолжается с того же места.
		self.channel:SetTime(0)
	end

	self:LoopTrack()
end

-- Меню персонажей и заставка Helix поднимают собственные каналы; глушим их,
-- чтобы в проекте оставался один источник звука. Helix начинает свой трек с
-- нулевой громкости и разгоняет её анимацией, поэтому склейка не слышна.
function MUSIC:SilenceHelixMusic()
	if (!self.bSilenceHelixMusic or !self.bWanted or !ix or !ix.gui) then
		return
	end

	for _, key in ipairs(self.helixMusicPanels) do
		local panel = ix.gui[key]

		if (IsValid(panel)) then
			local channel = panel.channel

			if (IsValid(channel) and !self.silencedChannels[channel]) then
				channel:Stop()
				self.silencedChannels[channel] = true
			end
		end
	end
end

-- =========================================================
-- ОСНОВНОЙ ЦИКЛ
-- =========================================================

function MUSIC:Think()
	self:SyncContexts()
	self:ValidateContexts()
	self:Update()
	self:SilenceHelixMusic()
	self:EnsureChannel()
	self:UpdateEnvelope()
	self:UpdateChannel()
	self:UpdateVolumeSaving()

	if (self.UpdateSliderHost) then
		self:UpdateSliderHost()
	end
end

function MUSIC:GetStatus()
	return {
		channel = IsValid(self.channel),
		state = IsValid(self.channel) and self.channel:GetState() or nil,
		loading = self.isLoading,
		wanted = self.bWanted,
		envelope = self.envelope,
		volume = self.volume,
		effectiveVolume = self:GetEffectiveVolume(),
		contexts = self.contexts,
		characterMenu = self:IsCharacterMenuOpen(),
		menu = self:IsMenuOpen(),
		intro = AfterlightIntro and (AfterlightIntro.active or AfterlightIntro.closing) and true or false,
		slider = IsValid(self.slider),
		sliderHost = self.sliderHost,
		-- Иконка громкости и состояние полосы (см. cl_volume_button.lua).
		button = IsValid(self.button),
		barOpen = self.bBarOpen == true
	}
end

hook.Add("Think", MUSIC.hookName, function()
	MUSIC:Think()
end)

-- =========================================================
-- ОТЛАДОЧНЫЕ КОМАНДЫ
-- =========================================================

concommand.Add("afterlight_music_play", function()
	MUSIC:SetContext("debug", true)
end)

concommand.Add("afterlight_music_stop", function()
	MUSIC:Stop()
end)

concommand.Add("afterlight_music_fade", function()
	MUSIC:FadeOut()
end)

concommand.Add("afterlight_music_volume", function(_, _, arguments)
	local value = tonumber(arguments[1])

	if (!value) then
		MsgN("[Afterlight Music] Использование: afterlight_music_volume <0-100>")

		return
	end

	-- Команда принимает проценты; 0 выключает музыку, но не останавливает трек.
	MUSIC:SetVolume(value / 100)
	MsgN("[Afterlight Music] Громкость: ", math.Round(MUSIC.volume * 100), "%")
end)

concommand.Add("afterlight_music_status", function()
	local status = MUSIC:GetStatus()

	print("========== Afterlight Music Status ==========")
	print("channel valid:", status.channel, "state:", status.state)
	print("loading:", status.loading, "wanted:", status.wanted)
	print("envelope:", math.Round(status.envelope, 3), "volume:", math.Round(status.volume, 3))
	print("effective volume:", math.Round(status.effectiveVolume, 3))

	for name in pairs(status.contexts) do
		print("context:", name)
	end

	print("character menu:", status.characterMenu, "helix menu:", status.menu, "intro:", status.intro)
	print("slider:", status.slider, "host:", status.sliderHost)
	print("volume button:", status.button, "bar open:", status.barOpen)
	print("============================================")
end)
