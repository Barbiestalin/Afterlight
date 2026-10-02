local PLUGIN = PLUGIN

ix.celerity = ix.celerity or {}

-- ЗВУКИ. Свои файлы кладутся в sound/afterlight/disciplines/celerity и
-- раздаются клиентам (resource.AddFile). Пока файла нет — фолбэк из
-- SOUND_FALLBACKS (активация слышна сразу); петля амбиента до появления
-- файла просто молчит, как у Могущества.
ix.celerity.SOUND_USE = "afterlight/disciplines/celerity/use.mp3"      -- звук активации
ix.celerity.SOUND_LOOP = "afterlight/disciplines/celerity/celerity.mp3" -- амбиент на время действия (цикл)
-- путь, куда файл амбиента может быть положен изначально; подхватывается,
-- если в основной папке его нет
ix.celerity.SOUND_LOOP_LEGACY = "disciplines/celerity/celerity.mp3"

-- Амбиент: громкость (ниже звука активации, чтобы не перекрикивать), пауза
-- после звука активации и длительность плавных входа/выхода в секундах.
ix.celerity.AMBIENT_VOLUME = 0.7
ix.celerity.AMBIENT_DELAY = 1.2
ix.celerity.AMBIENT_FADE = 1

-- Громкость личных звуков Стремительности (0..1) — крутить здесь.
ix.celerity.SOUND_VOLUME = 1

ix.celerity.SOUND_FALLBACKS = {
	activate = "ambient/wind/wind_med1.wav"
}

-- Параметры уровней по ТЗ: множители обычной скорости и спринта (shift),
-- временные пункты Ловкости (видны в чарлисте), множители скорости атаки
-- ближнего боя и перезарядки огнестрела, трейл «воздуха» (3+), уклонения
-- (4+ — первые 3 ближних попадания, 5 — первые 5 любых, включая огнестрел),
-- длительность и стоимость в витэ.
ix.celerity.LEVELS = {
	[1] = {walk = 1.25, run = 1.40, dexterity = 2, attack = 1.25, reload = 1.25, trail = 0, dodge = 0, dodgeBullets = false, duration = 10, vitae = 2},
	[2] = {walk = 1.40, run = 1.65, dexterity = 2, attack = 1.50, reload = 1.50, trail = 0, dodge = 0, dodgeBullets = false, duration = 15, vitae = 4},
	[3] = {walk = 1.60, run = 2.00, dexterity = 3, attack = 1.80, reload = 1.80, trail = 1, dodge = 0, dodgeBullets = false, duration = 15, vitae = 5},
	[4] = {walk = 1.80, run = 2.40, dexterity = 3, attack = 2.10, reload = 2.20, trail = 2, dodge = 3, dodgeBullets = false, duration = 20, vitae = 8},
	[5] = {walk = 2.10, run = 3.00, dexterity = 4, attack = 2.50, reload = 2.60, trail = 2, dodge = 5, dodgeBullets = true, duration = 20, vitae = 10}
}

function ix.celerity.GetLevelData(level)
	level = math.Clamp(math.floor(tonumber(level) or 0), 1, 5)
	return ix.celerity.LEVELS[level]
end

-- Активный уровень (0 — не активно). NW2-значения реплицируются, поэтому
-- функция общая для сервера и клиента.
function PLUGIN:GetActiveLevel(client)
	local level = client:GetNW2Int("afterlightCelerityLevel", 0)
	if (level > 0 and client:GetNW2Float("afterlightCelerityEnd", 0) > CurTime()) then
		return level
	end
	return 0
end

-- Временный бонус к Ловкости. ОБЯЗАТЕЛЬНО shared: чарлист рисует синие точки
-- на клиенте через GetCharacterVTMStatBonus (механизм afterlight_vtm_stats).
function PLUGIN:GetCharacterVTMStatBonus(character, statID)
	if (statID != "dexterity") then return end
	local client = character and character:GetPlayer()
	if (!IsValid(client)) then return end
	local level = self:GetActiveLevel(client)
	if (level > 0) then
		return ix.celerity.GetLevelData(level).dexterity
	end
end
