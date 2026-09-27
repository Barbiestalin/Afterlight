ix.potence = ix.potence or {}

ix.potence.UNITS_PER_METER = 39.37
-- Трещина на земле (уровни 3+) живёт 8 секунд серверного времени.
ix.potence.CRACK_LIFETIME = 8

-- ЗВУКИ. Кладите свои файлы в garrysmod/sound/afterlight/potence/ под этими
-- именами — код подхватит их автоматически и раздаст клиентам (resource.AddFile).
-- Пока файла нет, играет стоковый фолбэк из SOUND_FALLBACKS (эффект слышен сразу).
ix.potence.SOUND_JUMP = "afterlight/potence/jump_air.wav"          -- колебание воздуха при прыжке (2+)
ix.potence.SOUND_CRACK = "afterlight/potence/crack_impact.wav"     -- удар земли при прыжке (3+)
ix.potence.SOUND_HIT_LIGHT = "afterlight/potence/hit_light.wav"    -- особый удар, уровень 2, поверх обычного
ix.potence.SOUND_HIT_HEAVY = "afterlight/potence/hit_heavy.wav"    -- особый удар, уровни 3+, поверх обычного
ix.potence.SOUND_ACTIVATE = "afterlight/potence/activate.wav"      -- активация любого уровня

ix.potence.SOUND_FALLBACKS = {
	jump = "npc/vort/claw_swing2.wav",
	crack = "physics/concrete/concrete_break2.wav",
	hitLight = "physics/body/body_medium_impact_hard2.wav",
	hitHeavy = "physics/body/body_medium_impact_hard5.wav",
	activate = "physics/body/body_medium_impact_hard3.wav"
}

-- Параметры уровней по ТЗ: сила, добавочный урон ближнего боя, импульс
-- отброса (ед/с — подкручивать здесь), высота усиленного прыжка в метрах,
-- длительность, стоимость в витэ и выбивание дверей.
ix.potence.LEVELS = {
	[1] = {strength = 1, damage = 10, knockback = 300, jumpMeters = 0, duration = 10, vitae = 2, doors = false},
	[2] = {strength = 2, damage = 20, knockback = 420, jumpMeters = 2, duration = 15, vitae = 4, doors = false},
	[3] = {strength = 3, damage = 30, knockback = 550, jumpMeters = 4, duration = 15, vitae = 5, doors = false},
	[4] = {strength = 3, damage = 35, knockback = 700, jumpMeters = 5, duration = 20, vitae = 8, doors = true},
	[5] = {strength = 4, damage = 40, knockback = 850, jumpMeters = 7, duration = 25, vitae = 10, doors = true}
}

function ix.potence.GetLevelData(level)
	level = math.Clamp(math.floor(tonumber(level) or 0), 1, 5)
	return ix.potence.LEVELS[level]
end

-- Стартовая вертикальная скорость, чтобы достичь heightMeters при данной
-- гравитации: v = sqrt(2 * g * h). Возвращает единицы Source в секунду.
function ix.potence.JumpVelocity(heightMeters, gravity)
	gravity = tonumber(gravity) or 600
	return math.sqrt(2 * gravity * heightMeters * ix.potence.UNITS_PER_METER)
end
