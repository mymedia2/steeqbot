/* RolterBot — поисковик стикеров в Telegram
 * Copyright (c) Гурьев Николай, 2017
 *
 * Эта программа является свободным программным обеспечением: Вы можете
 * распространять её и (или) изменять, соблюдая условия Генеральной публичной
 * лицензии GNU Affero, опубликованной Фондом свободного программного
 * обеспечения; либо редакции 3 Лицензии, либо (на Ваше усмотрение) любой
 * редакции, выпущенной позже.
 *
 * Эта программа распространяется в расчёте на то, что она окажется полезной, но
 * БЕЗ КАКИХ-ЛИБО ГАРАНТИЙ, включая подразумеваемую гарантию КАЧЕСТВА либо
 * ПРИГОДНОСТИ ДЛЯ ОПРЕДЕЛЕННЫХ ЦЕЛЕЙ.
 *
 * Ознакомьтесь с Генеральной публичной лицензией GNU Affero для получения более
 * подробной информации. Вы должны были получить копию Генеральной публичной
 * лицензии GNU Affero вместе с этой программой. Если Вы ее не получили, то
 * перейдите по адресу: <https://www.gnu.org/licenses/agpl.html>.
 *
 * В этом файле содержится схема БД, используемая ботом (требуется SQLite v3).
 */

/* Количество отправок определённого стикера определённым пользователем по
 * определённому поисковому запросу (если не известен, то пустая строка).
 * Предполагается, что в поле words содержит только буквы, цифры или пробел.
 * Также содержится время последней отправки. Используется для сортировки
 * результатов поиска. Типы указываются в качестве подсказки. */
CREATE TABLE history (
    user_id INTEGER NOT NULL  /* ид отправителя */
  , file_id TEXT NOT NULL  /* ид стикера */
  , words TEXT NOT NULL DEFAULT ''
  , sendings_tally INTEGER NOT NULL DEFAULT 1
  , last_used_time INTEGER NOT NULL DEFAULT ( strftime('%s', 'now') )
  , UNIQUE (user_id, file_id, words)
);

/* Этот триггер используется для более удобного обновления счётчиков в таблице
 * истории. При попытке вставить конфликтующую запись, на самом деле
 * увеличивается счётчик в уже существующей записи. Если таковой нет, вставка
 * разрешается. */
CREATE TRIGGER sending
BEFORE INSERT ON history
BEGIN
  /* обновляем старую запись */
  UPDATE history
  SET sendings_tally = sendings_tally + NEW.sendings_tally
    , last_used_time = NEW.last_used_time
  WHERE user_id = NEW.user_id
    AND file_id = NEW.file_id
    AND words = NEW.words;
  /* и ничего не вставляем, если запись уже была */
  SELECT CASE WHEN changes() > 0 THEN RAISE (IGNORE) END;
END;

/* Доступные стикеры, известные боту (представление пока не используется) */
CREATE VIEW stickers AS
WITH t AS (SELECT DISTINCT file_id, words FROM history)
SELECT file_id, group_concat(words) AS description
FROM t WHERE words != '' GROUP BY file_id;

/* Пользователи, которые в текущий момент собираются дать описание стикера */
CREATE TABLE states (
    user_id INTEGER NOT NULL PRIMARY KEY
  , file_id TEXT NOT NULL
  , last_activity_time INTEGER NOT NULL DEFAULT ( strftime('%s', 'now') )
);
