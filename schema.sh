#!/bin/bash
sqlite "$@" <<EOF

CREATE TABLE favorites (
  user_id NOT NULL,
  file_id NOT NULL,
  UNIQUE ( user_id, file_id )
);

CREATE TABLE history (
  user_id NOT NULL,
  chat_id,
  file_id NOT NULL,
  counter NOT NULL,
  UNIQUE ( user_id, chat_id, file_id )
);

CREATE VIEW serchies AS
SELECT f.user_id, f.file_id, SUM ( ifnull ( h.counter, 0 ) ) AS counter
  FROM favorites AS f LEFT JOIN history AS h
    ON f.user_id = h.user_id AND f.file_id = h.file_id
GROUP BY f.user_id, f.file_id;

EOF
# vi: ft=sql
