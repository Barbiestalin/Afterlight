Afterlight Disciplines — контейнер вампирских дисциплин.

Структура:
  afterlight_disciplines/
    sh_plugin.lua            — этот контейнер;
    plugins/<дисциплина>/    — каждая дисциплина отдельным субплагином
                               (Helix сам загружает папку plugins/ плагина).

Первая дисциплина: plugins/potence (Могущество).

Интеграция:
  - уровни (точки) хранятся в afterlight_vtm_stats (чарлист);
  - выбор уровня и активация — через колесо afterlight_discipline_interface:
    каждый уровень зарегистрирован как отдельная способность (RegisterPower),
    витэ списывает интерфейсный шлюз (GetVitaeCost), там же кулдауны и сообщения;
  - временный бонус к Силе отображается синими точками в чарлисте через
    GetCharacterVTMStatBonus (механизм afterlight_vampire_abilities).

Звуки (будут добавлены отдельно, пути уже зарезервированы):
  sound/afterlight/potence/jump_air.wav    — колебание воздуха при прыжке (2+);
  sound/afterlight/potence/hit_light.wav   — удары уровней 1-2 поверх оружия;
  sound/afterlight/potence/hit_heavy.wav   — удары уровней 3+.
Пока файлов нет, код молчит и не пишет ошибок; после добавления подхватит сам.
