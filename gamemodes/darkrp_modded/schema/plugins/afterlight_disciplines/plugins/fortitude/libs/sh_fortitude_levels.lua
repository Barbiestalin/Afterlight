local PLUGIN = PLUGIN

ix.fortitude = ix.fortitude or {}

-- ЗВУК. Единственный файл дисциплины: короткий каменный гул, играется один
-- раз в момент активации (не цикл). Пока лежит заглушка — заменим файл тем же
-- путём, код трогать не придётся. Файл раздаётся клиентам (resource.AddFile).
ix.fortitude.SOUND_PATH = "afterlight/disciplines/fortitude/fortitude.wav"

-- Громкость звука активации Стойкости (0..1) — крутить здесь.
ix.fortitude.SOUND_VOLUME = 0.9

-- Регенерация пассивного барьера: скорость (ед./сек) и пауза без урона, после
-- которой восстановление начинается (решения опроса: 5 ед./сек, 20 секунд).
ix.fortitude.REGEN_RATE = 5
ix.fortitude.REGEN_DELAY = 20

-- Параметры уровней по ТЗ: пассивный барьер (постоянно от точек в чарлисте),
-- добавочный барьер при активации (поверх текущего, сгорает до пассивного
-- максимума в конце действия), поглощение урона с каждой атаки на время
-- действия, временные пункты Выносливости, длительность, стоимость в витэ и
-- откат (на 5-м уровне — 40 секунд, на остальных — 30).
ix.fortitude.LEVELS = {
	[1] = {passive = 25, bonus = 25, absorb = 5, stamina = 1, duration = 10, vitae = 4, cooldown = 30},
	[2] = {passive = 35, bonus = 35, absorb = 10, stamina = 1, duration = 12, vitae = 6, cooldown = 30},
	[3] = {passive = 45, bonus = 45, absorb = 15, stamina = 2, duration = 15, vitae = 10, cooldown = 30},
	[4] = {passive = 60, bonus = 70, absorb = 20, stamina = 3, duration = 15, vitae = 12, cooldown = 30},
	[5] = {passive = 70, bonus = 100, absorb = 25, stamina = 4, duration = 20, vitae = 15, cooldown = 40}
}

function ix.fortitude.GetLevelData(level)
	level = math.Clamp(math.floor(tonumber(level) or 0), 1, 5)
	return ix.fortitude.LEVELS[level]
end

-- Активный уровень (0 — не активно). NW2-значения реплицируются, поэтому
-- функция общая для сервера и клиента.
function PLUGIN:GetActiveLevel(client)
	local level = client:GetNW2Int("afterlightFortitudeLevel", 0)
	if (level > 0 and client:GetNW2Float("afterlightFortitudeEnd", 0) > CurTime()) then
		return level
	end
	return 0
end

-- Временный бонус к Выносливости. ОБЯЗАТЕЛЬНО shared: чарлист рисует синие
-- точки на клиенте через GetCharacterVTMStatBonus (механизм
-- afterlight_vtm_stats / afterlight_vampire_abilities).
function PLUGIN:GetCharacterVTMStatBonus(character, statID)
	if (statID != "stamina") then return end
	local client = character and character:GetPlayer()
	if (!IsValid(client)) then return end
	local level = self:GetActiveLevel(client)
	if (level > 0) then
		return ix.fortitude.GetLevelData(level).stamina
	end
end
