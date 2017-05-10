#!/bin/bash

# Depends: jshon netcat-openbsd curl openssl sqlite3

set -o errexit pipefail
source api.sh
source database.sh

function process_message {
  # TODO: сделать, чтобы start_bot не вызывала эту функцию
  : pass
}

function process_start_command {
  local chat=$(jshon -e chat -e id)
  local msg="\
Привет! Я могу помочь найти тебе подходящий стикер именно в тот момент, когда \
он очень нужен. Чтобы вызвать меня, просто набери моё имя в строке сообщения, \
а затем введи cвой запрос."
  local kbd='{"inline_keyboard":[[
    {"text":"↪️ Опробовать...","switch_inline_query":""} ]]}'
  tg::api_call sendMessage text="${msg}" chat_id="${chat}" \
    reply_markup="${kbd}" >/dev/null
}

function process_help_command {
  local chat=$(jshon -e from -e id)
  local msg="\
Я – бот-помощник в поиске стикеров. Просто напиши мне, какой стикер тебя \
интересует, и я попытаюсь найти его. Но помни, пока мне известно очень мало \
стикеров, поэтому поиск может быть нерезультативным. Если тебя расстраивает \
эта ситуация, отправь мне в личку свои любимые стикеры, и со временем я их \
проиндексирую."
  tg::api_call sendMessage text="${msg}" chat_id="${chat}" >/dev/null
}

function process_sticker {
  local message=$(cat)
  local user_id=$(echo "${message}" | jshon -e from -e id)
  local file_id=$(echo "${message}" | jshon -e sticker -e file_id)
  if echo "${message}" | jshon -e chat -e type | grep -q private; then
    if sql::query "SELECT COUNT(*) FROM history WHERE user_id = ${user_id}
                   AND file_id = ${file_id}" | grep -q 0; then
      if (( RANDOM % 2 )); then
        local msg="Ого какой интересный стикер!"
      else
        local msg="Ого какой красивый стикер!"
      fi
      if (( RANDOM % 2 )); then
        msg+=" А что на нём изображено?"
      else
        msg+=" А что тут изображено?"
      fi
    else
      local msg="О! А этот стикер уже знаю 😃"
    fi
    tg::api_call sendMessage text="${msg}" chat_id="${user_id}" \
      reply_markup='{"force_reply":true}' >/dev/null
    sql::query "INSERT INTO history (user_id, file_id, sendings_tally)
                VALUES (${user_id}, ${file_id}, 0);
                REPLACE INTO states (user_id, file_id)
                VALUES (${user_id}, ${file_id})"
  else
    sql::query "INSERT INTO history (user_id, file_id)
                VALUES (${user_id}, ${file_id})"
  fi
}

function process_inline_query {
  local update=$(cat)
  local query_id=$(echo "${update}" | jshon -e id -u)
  local user_id=$(echo "${update}" | jshon -e from -e id)
  local pattern=$(echo "${update}" | jshon -e query -u | sed 's/"/""/g')
  local stickers_json=[$(sql::query "
    WITH r AS (SELECT *, 1 AS category FROM history
               WHERE words LIKE \"%${pattern}%\"
               ORDER BY sendings_tally DESC, user_id != ${user_id}),
         m AS (SELECT *, 0 AS category FROM history WHERE words = ''
               ORDER BY sendings_tally DESC, user_id != ${user_id}
               LIMIT (SELECT count(*) FROM r) / 3)
    SELECT DISTINCT file_id FROM r UNION SELECT DISTINCT file_id FROM m
    LIMIT 50" \
      | sed 's/.*/{"type":"sticker","id":"\0","sticker_file_id":"\0"}/
             2~1s/.*/,\0/')]
  tg::api_call answerInlineQuery inline_query_id="${query_id}" \
    results="${stickers_json}" cache_time=1 is_personal=true >/dev/null
}

function process_chosen_inline_result {
  local result=$(cat)
  local file_id=$(echo "${result}" | jshon -e result_id)
  local user_id=$(echo "${result}" | jshon -e from -e id)
  local words=$(echo "${result}" | jshon -e query -u | sql::to_literal)
  sql::query "INSERT INTO history (user_id, file_id, words)
              VALUES (${user_id}, ${file_id}, ${words})"
}

function process_text {
  local query=$(cat)
  echo "${query}" | jshon -e chat -e type | grep -q private || return 0
  local user_id=$(echo "${query}" | jshon -e from -e id)
  local pattern=$(echo "${query}" | jshon -e text -u | sed 's/"/""/g')
  local file_id=$(sql::query "
    SELECT file_id FROM history WHERE words LIKE \"%${pattern}%\"
    ORDER BY sendings_tally DESC, user_id != ${user_id} LIMIT 1")
  if [ -z "${file_id}" ]; then
    tg::api_call sendMessage chat_id="${user_id}" \
      text="К сожалению, по этому запросу ничего не нашлось 😔" >/dev/null
  else
    tg::api_call sendSticker chat_id="${user_id}" sticker="${file_id}" >/dev/null
  fi
}

function process_reply {
  local data=$(cat)
  echo "${data}" | jshon -e chat -e type | grep -q private || return 0
  local user_id=$(echo "${data}" | jshon -e from -e id)
  local description=$(echo "${data}" | jshon -e text)
  local file_id=$(echo "${data}" \
    | jshon -Q -e reply_to_message -e sticker -e file_id)
  if [ -n "${description}" ]; then
    local res=true
    if [ -n "${file_id}" ]; then
      sql::query "
        INSERT INTO history (user_id, file_id, words, sendings_tally)
        VALUES (${user_id}, ${file_id}, ${description}, 0)"
    else
      sql::query "
        INSERT INTO history (user_id, words, sendings_tally, file_id)
        VALUES (${user_id}, ${description}, 0,
        (SELECT file_id FROM states WHERE user_id = ${user_id}))" || res=false
    fi
    if [ "${res}" = true ]; then
      tg::api_call sendMessage text="Понятно 🙂" chat_id="${user_id}" >/dev/null
    fi
  fi
}

tg::start_bot "message,inline_query,chosen_inline_result" "start,help" \
  "text,sticker,reply"
