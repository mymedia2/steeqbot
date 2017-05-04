/* Схема БД, используемая ботом (требуется SQLite v3) */

CREATE TABLE favorites (
  user_id NOT NULL,
  file_id NOT NULL,
  UNIQUE (user_id, file_id)
);

CREATE TABLE history (
  user_id   NOT NULL,
  chat_id,
  file_id   NOT NULL,
  counter   NOT NULL,
  last_used NOT NULL,
  UNIQUE (user_id, chat_id, file_id)
);

  CREATE VIEW finding AS
  SELECT f.user_id, f.file_id, SUM(ifnull(h.counter, 0)) AS counter
    FROM favorites AS f
         LEFT JOIN history AS h
         ON f.user_id = h.user_id
            AND f.file_id = h.file_id
GROUP BY f.user_id, f.file_id;

CREATE TRIGGER sending_of_existing
BEFORE INSERT ON history
BEGIN
  /* не трогаем недавно изменённую запись */
  SELECT CASE
    WHEN NEW.last_used - (SELECT MAX(last_used)
                            FROM history
                           WHERE user_id = NEW.user_id
                             AND file_id = NEW.file_id) <= 1
    THEN RAISE(IGNORE) END;
  /* обновляем старую запись */
  UPDATE history
     SET counter = counter + NEW.counter
       , last_used = NEW.last_used
   WHERE user_id = NEW.user_id
     AND (chat_id = NEW.chat_id OR chat_id IS NULL AND NEW.chat_id IS NULL)
     AND file_id = NEW.file_id;
  /* и ничего не вставляем */
  SELECT CASE WHEN CHANGES() > 0 THEN RAISE(IGNORE) END;
END;
