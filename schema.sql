/* Схема БД, используемая ботом (требуется SQLite v3) */

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
