#!/bin/bash

set -o errexit pipefail
source api.sh

function db_query {
  echo "$@;" >&2
  sqlite stickers.db "$@"
}

function process_message {
  # TODO: сделать, чтобы start_bot не вызывала эту функцию
  local message=$(cat)
  local msg_text=$(echo "${message}" | jshon -e text -u)
  local msg_chat=$(echo "${message}" | jshon -e chat -e id)
  tg::api_call sendMessage text="${msg_text}" chat_id="${msg_chat}" >/dev/null
}

function process_start_command {
  local chat=$(jshon -e chat -e id)
  local msg="\
Привет! Я могу помочь найти тебе подходящий стикер именно в тот момент, \
когда он очень нужен. Чтобы вызвать меня, просто набери моё имя в строке \
сообщения, а затем введи cвой запрос."
  local kbd='{"inline_keyboard":[[
    {"text":"↪️ Опробовать...","switch_inline_query":""} ]]}'
  tg::api_call sendMessage text="${msg}" chat_id="${chat}" \
    reply_markup="${kbd}" >/dev/null
}

function process_list_command {
  echo list command
  cat
}

function process_sticker {
  local message=$(cat)
  local user_id=$(echo "${message}" | jshon -e from -e id)
  local chat_id=$(echo "${message}" | jshon -e chat -e id)
  local file_id=$(echo "${message}" | jshon -e sticker -e file_id)
  if echo "${message}" | jshon -e chat -e type | grep -q private; then
    if db_query "INSERT INTO favorites VALUES (${user_id}, ${file_id})"; then
      local msg="ок!"
    else
      local msg="Этот стикер уже есть в наборе"
    fi
    tg::api_call sendMessage text="${msg}" chat_id="${user_id}" >/dev/null
  else
    db_query "REPLACE INTO history VALUES (${user_id}, ${chat_id}, ${file_id},
      ifnull((SELECT counter + 1 FROM history
              WHERE user_id = ${user_id} AND file_id = ${file_id}), 1))"
  fi
}

function process_inline_query {
  local update=$(cat)
  local query_id=$(echo "${update}" | jshon -e id -u)
  local user_id=$(echo "${update}" | jshon -e from -e id)
  local stickers_json=[$(
    db_query "SELECT file_id FROM serchies WHERE user_id = ${user_id}
              ORDER BY counter DESC LIMIT 50" \
      | sed 's/.*/{"type":"sticker","id":"\0","sticker_file_id":"\0"}/
             2~1s/.*/,\0/')]
  if [ "${stickers_json}" = "[]" ]; then
    local swp=(
      switch_pm_text="Задай свой набор стикеров..."
      switch_pm_parameter="new_set"
    )
  fi
  tg::api_call answerInlineQuery inline_query_id="${query_id}" cache_time=1 \
    results="${stickers_json}" is_personal=true "${swp[@]}" >/dev/null
}

function process_chosen_inline_result {
  local result=$(cat)
  local file_id=$(echo "${result}" | jshon -e result_id)
  local user_id=$(echo "${result}" | jshon -e from -e id)
  db_query "REPLACE INTO history (user_id, file_id, counter)
            SELECT user_id, file_id, counter + 1 FROM history
            WHERE user_id = ${user_id} AND file_id = ${file_id}
            UNION ALL SELECT ${user_id}, ${file_id}, 1 LIMIT 1"
}

tg::start_bot "message,inline_query,chosen_inline_result" "start,list" "sticker"
