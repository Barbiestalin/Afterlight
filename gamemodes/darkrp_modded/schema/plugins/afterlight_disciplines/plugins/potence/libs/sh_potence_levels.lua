local PLUGIN = PLUGIN

ix.potence = ix.potence or {}

ix.potence.UNITS_PER_METER = 39.37
-- Трещина на земле (уровни 3+) живёт 8 секунд серверного времени.
ix.potence.CRACK_LIFETIME = 8

-- ЗВУКИ. Свои файлы use/punch/door лежат в ветке (sound/afterlight/disciplines/potence)
-- и раздаются клиентам (resource.AddFile). Пока своего файла нет, играет
-- стоковый фолбэк из SOUND_FALLBACKS (эффект слышен сразу).
ix.potence.SOUND_USE = "afterlight/disciplines/potence/use.mp3"      -- звучит при активации/использовании Могущества
ix.potence.SOUND_PUNCH = "afterlight/disciplines/potence/punch.mp3"  -- особый удар (2+), поверх стандартного звука HL2
ix.potence.SOUND_DOOR = "afterlight/disciplines/potence/door.mp3"    -- выбивание двери (4+)
ix.potence.SOUND_JUMP = "afterlight/disciplines/potence/jump_air.wav"      -- колебание воздуха при прыжке (2+)
ix.potence.SOUND_CRACK = "afterlight/disciplines/potence/crack_impact.wav" -- удар земли при прыжке (3+)
ix.potence.SOUND_LOOP = "afterlight/disciplines/potence/potence.mp3" -- амбиент на время действия (цикл)
-- путь, куда файл амбиента положен изначально; подхватывается, если в основной папке его нет
ix.potence.SOUND_LOOP_LEGACY = "disciplines/potence/potence.mp3"
-- Амбиент: громкость (ниже звука активации, чтобы не перекрикивать), пауза
-- после звука активации и длительность плавных входа/выхода в секундах.
ix.potence.AMBIENT_VOLUME = 0.7
ix.potence.AMBIENT_DELAY = 1.2
ix.potence.AMBIENT_FADE = 1

-- Громкость личных/зонных звуков Могущества (0..1) — крутить здесь.
ix.potence.SOUND_VOLUME = 1
-- Радиус слышимости удара (ед.; 300 ≈ 7.5 метров) — крутить здесь.
ix.potence.PUNCH_RADIUS = 300

ix.potence.SOUND_FALLBACKS = {
	jump = "npc/vort/claw_swing2.wav",
	crack = "physics/concrete/concrete_break2.wav",
	hitLight = "physics/body/body_medium_impact_hard2.wav",
	hitHeavy = "physics/body/body_medium_impact_hard5.wav",
	activate = "physics/body/body_medium_impact_hard3.wav",
	doorKick = "physics/wood/wood_crate_impact_hard2.wav"
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

-- Активный уровень (0 — не активно). NW2-значения реплицируются, поэтому
-- функция общая для сервера и клиента.
function PLUGIN:GetActiveLevel(client)
	local level = client:GetNW2Int("afterlightPotenceLevel", 0)
	if (level > 0 and client:GetNW2Float("afterlightPotenceEnd", 0) > CurTime()) then
		return level
	end
	return 0
end

-- Временный бонус к Силе. ОБЯЗАТЕЛЬНО shared: чарлист рисует синие точки на
-- клиенте через GetCharacterVTMStatBonus — у BloodBuff (Vampire Abilities)
-- этот хук живёт в shared-файле, поэтому его точки и появляются.
function PLUGIN:GetCharacterVTMStatBonus(character, statID)
	if (statID != "strength") then return end
	local client = character and character:GetPlayer()
	if (!IsValid(client)) then return end
	local level = self:GetActiveLevel(client)
	if (level > 0) then
		return ix.potence.GetLevelData(level).strength
	end
end
