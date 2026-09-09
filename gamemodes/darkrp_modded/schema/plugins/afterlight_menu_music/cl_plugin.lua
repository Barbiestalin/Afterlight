if (!CLIENT) then return end

-- =========================================================
-- CLEANUP ПРИ LUA_REFRESH
-- =========================================================

timer.Remove("AfterlightMusicController")
timer.Remove("AfterlightMusicFadeOut")
timer.Remove("AfterlightMusicStateSanityCheck")

hook.Remove("ScoreboardShow", "AfterlightMusicScoreboardShow")
hook.Remove("ScoreboardHide", "AfterlightMusicScoreboardHide")
hook.Remove("CharacterLoaded", "AfterlightMusicCharacterLoaded")
hook.Remove("OnCharacterDisconnect", "AfterlightMusicCharacterDisconnect")
hook.Remove("Think", "AfterlightMusicCharacterMenuWatcher")

concommand.Remove("afterlight_music_play")
concommand.Remove("afterlight_music_stop")
concommand.Remove("afterlight_music_fade")
concommand.Remove("afterlight_music_status")

AfterlightMusic = AfterlightMusic or {}

-- =========================================================
-- НАСТРОЙКИ
-- =========================================================

AfterlightMusic.path = "sound/afterlight/intro_music.mp3"

AfterlightMusic.volume = math.Clamp(tonumber(cookie.GetString("afterlight_music_volume", "0.75")) or 0.75, 0, 1)
AfterlightMusic.fadeFraction = 1
AfterlightMusic.fadeTime = 3
AfterlightMusic.checkInterval = 0.25

-- Сколько секунд не гасить музыку после закрытия TAB,
-- чтобы Helix успел открыть меню персонажей.
AfterlightMusic.characterMenuGraceTime = 2

-- Через сколько секунд после закрытия меню персонажей проверять затухание.
AfterlightMusic.characterMenuCloseDelay = 0.5

-- =========================================================
-- СОСТОЯНИЕ
-- =========================================================

AfterlightMusic.channel = AfterlightMusic.channel or nil
AfterlightMusic.isLoading = false
AfterlightMusic.isFading = false
AfterlightMusic.shouldPlay = false

-- Интро активно.
AfterlightMusic.introActive = AfterlightMusic.introActive or false

-- Игрок находится в режиме выбора персонажа.
AfterlightMusic.waitingForCharacterSelection = AfterlightMusic.waitingForCharacterSelection or false

-- TAB / scoreboard / игровое меню.
AfterlightMusic.forceGameMenuMusic = false

-- Переходный период при открытии меню персонажей из TAB.
AfterlightMusic.characterMenuGraceUntil = AfterlightMusic.characterMenuGraceUntil or 0

-- Для отслеживания открытия/закрытия character menu.
AfterlightMusic.lastCharacterMenuOpen = false

-- =========================================================
-- БАЗОВЫЕ ФУНКЦИИ
-- =========================================================

function AfterlightMusic:IsChannelValid()
	return IsValid(self.channel)
end

function AfterlightMusic:GetState()
	if (!self:IsChannelValid()) then
		return nil
	end

	return self.channel:GetState()
end

function AfterlightMusic:IsPlaying()
	return self:GetState() == GMOD_CHANNEL_PLAYING
end

function AfterlightMusic:IsPaused()
	return self:GetState() == GMOD_CHANNEL_PAUSED
end

-- transient: применить сразу, но записать cookie только после завершения жеста.
function AfterlightMusic:SetVolume(volume, transient)
	self.volume = math.Clamp(tonumber(volume) or self.volume, 0, 1)

	if (self:IsChannelValid()) then
		self.channel:SetVolume(self.volume * (self.isFading and self.fadeFraction or 1))
	end

	if (!transient) then
		cookie.Set("afterlight_music_volume", tostring(self.volume))
	end
end

-- =========================================================
-- РЕЖИМ МЕНЮ ПЕРСОНАЖЕЙ
-- =========================================================

function AfterlightMusic:EnterCharacterMenuMode()
	self.waitingForCharacterSelection = true
	self.characterMenuGraceUntil = CurTime() + self.characterMenuGraceTime

	self:Play()
end

function AfterlightMusic:LeaveCharacterMenuMode()
	self.waitingForCharacterSelection = false
	self.characterMenuGraceUntil = 0
end

-- =========================================================
-- ЗАПУСК МУЗЫКИ
-- =========================================================

function AfterlightMusic:Play()
	self.shouldPlay = true

	timer.Remove("AfterlightMusicFadeOut")
	self.isFading = false

	-- Если канал уже есть — НЕ создаём новый.
	if (self:IsChannelValid()) then
		self.channel:SetVolume(self.volume)

		if (!self:IsPlaying()) then
			self.channel:Play()
		end

		return
	end

	-- Если PlayFile уже грузится — второй раз не запускаем.
	if (self.isLoading) then
		return
	end

	self.isLoading = true

	sound.PlayFile(self.path, "noplay", function(channel, errorID, errorName)
		self.isLoading = false

		if (!IsValid(channel)) then
			return
		end

		if (!self.shouldPlay) then
			channel:Stop()
			return
		end

		if (self:IsChannelValid() and self.channel != channel) then
			channel:Stop()
			return
		end

		self.channel = channel
		self.channel:SetVolume(self.volume)
		self.channel:Play()
	end)
end

-- =========================================================
-- МГНОВЕННАЯ ОСТАНОВКА
-- =========================================================

function AfterlightMusic:Stop()
	self.shouldPlay = false
	self.isLoading = false
	self.isFading = false

	timer.Remove("AfterlightMusicFadeOut")

	if (self:IsChannelValid()) then
		self.channel:Stop()
	end

	self.channel = nil
end

-- =========================================================
-- ПЛАВНОЕ ЗАТУХАНИЕ
-- =========================================================

function AfterlightMusic:FadeOut(fadeTime)
	self.shouldPlay = false

	if (!self:IsChannelValid()) then
		return
	end

	if (self.isFading) then
		return
	end

	self.isFading = true

	local channel = self.channel
	local startFraction = self.volume > 0 and math.Clamp(channel:GetVolume() / self.volume, 0, 1) or 1
	self.fadeFraction = startFraction
	local startTime = CurTime()
	local duration = math.max(fadeTime or self.fadeTime, 0.01)

	timer.Remove("AfterlightMusicFadeOut")

	timer.Create("AfterlightMusicFadeOut", 0.03, 0, function()
		if (!IsValid(channel)) then
			timer.Remove("AfterlightMusicFadeOut")

			if (self.channel == channel) then
				self.channel = nil
			end

			self.isFading = false
			return
		end

		-- Если музыка снова понадобилась — отменяем затухание.
		if (self.shouldPlay) then
			channel:SetVolume(self.volume)
			self.isFading = false
			timer.Remove("AfterlightMusicFadeOut")
			return
		end

		local progress = math.Clamp((CurTime() - startTime) / duration, 0, 1)
		self.fadeFraction = Lerp(progress, startFraction, 0)

		channel:SetVolume(self.volume * self.fadeFraction)

		if (progress >= 1) then
			channel:Stop()

			if (self.channel == channel) then
				self.channel = nil
			end

			self.isFading = false
			timer.Remove("AfterlightMusicFadeOut")
		end
	end)
end

-- =========================================================
-- ЗАЦИКЛИВАНИЕ
-- =========================================================

function AfterlightMusic:ThinkLoop()
	if (!self.shouldPlay) then return end
	if (!self:IsChannelValid()) then return end

	local length = self.channel:GetLength()
	local time = self.channel:GetTime()

	if (!length or length <= 0) then return end
	if (!time) then return end

	if (time >= length - 0.2) then
		self.channel:SetTime(0)
		self.channel:Play()
	end
end

-- =========================================================
-- ПРОВЕРКА МЕНЮ ПЕРСОНАЖА
-- =========================================================

function AfterlightMusic:IsCharacterMenuOpen()
	if (!ix or !ix.gui) then
		return false
	end

	if (IsValid(ix.gui.characterMenu) and ix.gui.characterMenu:IsVisible()) then
		return true
	end

	return false
end

function AfterlightMusic:IsCharacterMenuGraceActive()
	return CurTime() < (self.characterMenuGraceUntil or 0)
end

-- =========================================================
-- ПРОВЕРКА TAB / ИГРОВОГО МЕНЮ
-- =========================================================

function AfterlightMusic:IsHelixGameMenuOpen()
	if (self.forceGameMenuMusic) then
		return true
	end

	if (!ix or !ix.gui) then
		return false
	end

	if (IsValid(ix.gui.menu) and ix.gui.menu:IsVisible()) then
		return true
	end

	if (IsValid(ix.gui.mainMenu) and ix.gui.mainMenu:IsVisible()) then
		return true
	end

	if (IsValid(ix.gui.tabMenu) and ix.gui.tabMenu:IsVisible()) then
		return true
	end

	return false
end

-- =========================================================
-- ПРОВЕРКА НАЛИЧИЯ ПЕРСОНАЖА
-- =========================================================

function AfterlightMusic:HasCharacter()
	local client = LocalPlayer()

	if (!IsValid(client)) then
		return false
	end

	if (client.GetCharacter and client:GetCharacter()) then
		return true
	end

	return false
end

-- =========================================================
-- НУЖНО ЛИ ИГРАТЬ СЕЙЧАС
-- =========================================================

function AfterlightMusic:ShouldPlayNow()
	local hasCharacter = self:HasCharacter()
	local characterMenuOpen = self:IsCharacterMenuOpen()
	local graceActive = self:IsCharacterMenuGraceActive()
	local gameMenuOpen = self:IsHelixGameMenuOpen()

	-- 1. Интро.
	if (self.introActive) then
		return true
	end

	-- 2. Реально открыто меню персонажей.
	if (characterMenuOpen) then
		return true
	end

	-- 3. Переход из TAB в меню персонажей.
	if (graceActive) then
		return true
	end

	-- 4. Ожидание выбора персонажа после интро.
	-- Держим музыку только если персонаж ещё не выбран.
	if (self.waitingForCharacterSelection and !hasCharacter) then
		return true
	end

	-- 5. TAB / игровое меню.
	if (gameMenuOpen) then
		return true
	end

	return false
end

-- =========================================================
-- ОСНОВНОЙ КОНТРОЛЛЕР
-- =========================================================

timer.Create("AfterlightMusicController", AfterlightMusic.checkInterval, 0, function()
	if (!AfterlightMusic) then return end

	AfterlightMusic:ThinkLoop()

	local shouldPlay = AfterlightMusic:ShouldPlayNow()

	if (shouldPlay) then
		if (AfterlightMusic.isFading or (!AfterlightMusic:IsPlaying() and !AfterlightMusic.isLoading)) then
			AfterlightMusic:Play()
		end
	else
		if (AfterlightMusic:IsPlaying()) then
			AfterlightMusic:FadeOut()
		end
	end
end)

-- =========================================================
-- WATCHER МЕНЮ ПЕРСОНАЖЕЙ
-- =========================================================

hook.Add("Think", "AfterlightMusicCharacterMenuWatcher", function()
	if (!AfterlightMusic) then return end

	local isOpen = AfterlightMusic:IsCharacterMenuOpen()
	local wasOpen = AfterlightMusic.lastCharacterMenuOpen

	-- Меню персонажей открылось.
	if (isOpen and !wasOpen) then
		AfterlightMusic.waitingForCharacterSelection = true
		AfterlightMusic.characterMenuGraceUntil = 0

		AfterlightMusic:Play()
	end

	-- Меню персонажей закрылось.
	if (!isOpen and wasOpen) then
		timer.Simple(AfterlightMusic.characterMenuCloseDelay, function()
			if (!AfterlightMusic) then return end

			if (!AfterlightMusic:ShouldPlayNow()) then
				AfterlightMusic.waitingForCharacterSelection = false
				AfterlightMusic.characterMenuGraceUntil = 0
				AfterlightMusic:FadeOut()
			end
		end)
	end

	AfterlightMusic.lastCharacterMenuOpen = isOpen
end)

-- =========================================================
-- TAB / SCOREBOARD
-- =========================================================

hook.Add("ScoreboardShow", "AfterlightMusicScoreboardShow", function()
	if (!AfterlightMusic) then return end

	AfterlightMusic.forceGameMenuMusic = true
	AfterlightMusic:Play()
end)

hook.Add("ScoreboardHide", "AfterlightMusicScoreboardHide", function()
	if (!AfterlightMusic) then return end

	AfterlightMusic.forceGameMenuMusic = false

	-- Даём время Helix открыть меню персонажей, если игрок нажал его из TAB.
	AfterlightMusic.characterMenuGraceUntil = CurTime() + AfterlightMusic.characterMenuGraceTime

	timer.Simple(AfterlightMusic.characterMenuGraceTime, function()
		if (!AfterlightMusic) then return end

		if (!AfterlightMusic:IsCharacterMenuOpen()) then
			AfterlightMusic.characterMenuGraceUntil = 0
		end

		if (!AfterlightMusic:ShouldPlayNow()) then
			AfterlightMusic:FadeOut()
		end
	end)
end)

-- =========================================================
-- ВЫБОР ПЕРСОНАЖА
-- =========================================================

hook.Add("CharacterLoaded", "AfterlightMusicCharacterLoaded", function(character)
	if (!AfterlightMusic) then return end

	timer.Simple(0.75, function()
		if (!AfterlightMusic) then return end

		AfterlightMusic.introActive = false
		AfterlightMusic.waitingForCharacterSelection = false
		AfterlightMusic.characterMenuGraceUntil = 0

		if (AfterlightMusic:ShouldPlayNow()) then
			AfterlightMusic:Play()
		else
			AfterlightMusic:FadeOut()
		end
	end)
end)

-- На случай выхода обратно в меню персонажей.
hook.Add("OnCharacterDisconnect", "AfterlightMusicCharacterDisconnect", function()
	if (!AfterlightMusic) then return end

	AfterlightMusic:EnterCharacterMenuMode()
end)

-- =========================================================
-- ДОПОЛНИТЕЛЬНАЯ ЗАЩИТА
-- =========================================================

timer.Create("AfterlightMusicStateSanityCheck", 1, 0, function()
	if (!AfterlightMusic) then return end

	if (
		AfterlightMusic.waitingForCharacterSelection and
		AfterlightMusic:HasCharacter() and
		!AfterlightMusic:IsCharacterMenuOpen() and
		!AfterlightMusic:IsHelixGameMenuOpen() and
		!AfterlightMusic.introActive
	) then
		AfterlightMusic.waitingForCharacterSelection = false
		AfterlightMusic.characterMenuGraceUntil = 0

		if (!AfterlightMusic:ShouldPlayNow()) then
			AfterlightMusic:FadeOut()
		end
	end
end)

-- =========================================================
-- ТЕСТОВЫЕ КОМАНДЫ
-- =========================================================

concommand.Add("afterlight_music_play", function()
	AfterlightMusic:Play()
end)

concommand.Add("afterlight_music_stop", function()
	AfterlightMusic:Stop()
end)

concommand.Add("afterlight_music_fade", function()
	AfterlightMusic:FadeOut()
end)

concommand.Add("afterlight_music_status", function()
	print("========== Afterlight Music Status ==========")
	print("channel valid:", AfterlightMusic:IsChannelValid())
	print("is loading:", AfterlightMusic.isLoading)
	print("is fading:", AfterlightMusic.isFading)
	print("is playing:", AfterlightMusic:IsPlaying())
	print("should play:", AfterlightMusic.shouldPlay)
	print("intro active:", AfterlightMusic.introActive)
	print("waiting character selection:", AfterlightMusic.waitingForCharacterSelection)
	print("character menu open:", AfterlightMusic:IsCharacterMenuOpen())
	print("character menu grace:", AfterlightMusic:IsCharacterMenuGraceActive())
	print("game menu open:", AfterlightMusic:IsHelixGameMenuOpen())
	print("has character:", AfterlightMusic:HasCharacter())
	print("============================================")
end)