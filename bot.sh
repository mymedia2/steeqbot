#!/bin/bash

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
Привет! Я могу помочь найти тебе подходящий стикер именно в тот момент, \
когда он очень нужен. Чтобы вызвать меня, просто набери моё имя в строке \
сообщения, а затем введи cвой запрос."
  local kbd='{"inline_keyboard":[[
    {"text":"↪️ Опробовать...","switch_inline_query":""} ]]}'
  tg::api_call sendMessage text="${msg}" chat_id="${chat}" \
    reply_markup="${kbd}" >/dev/null
}

function process_help_command {
  local chat=$(jshon -e from -e id)
  local msg="\
Пока только реализована возможность запоминания любимых стикеров. Просто \
отправь мне стикеры, которые тебе нравятся, и я буду предлагать их тебе при \
поиске.  Список сортируется по частоте использования. Можно добавить меня в \
групповой чат, и я буду учитывать использование стикеров там."
  tg::api_call sendMessage text="${msg}" chat_id="${chat}" >/dev/null
}

function process_sticker {
  local message=$(cat)
  local user_id=$(echo "${message}" | jshon -e from -e id)
  local chat_id=$(echo "${message}" | jshon -e chat -e id)
  local file_id=$(echo "${message}" | jshon -e sticker -e file_id)
  if echo "${message}" | jshon -e chat -e type | grep -q private; then
    if sql::query "INSERT INTO favorites VALUES (${user_id}, ${file_id})"; then
      local msg="ок!"
    else
      local msg="Этот стикер уже есть в наборе"
    fi
    tg::api_call sendMessage text="${msg}" chat_id="${user_id}" >/dev/null
  else
    sql::query "
      REPLACE INTO history (user_id, chat_id, file_id, counter, last_used)
      VALUES (${user_id}, ${chat_id}, ${file_id}, 1, strftime('%s', 'now'))"
  fi
}

function process_inline_query {
  local update=$(cat)
  local query_id=$(echo "${update}" | jshon -e id -u)
  local user_id=$(echo "${update}" | jshon -e from -e id)
  local stickers_json=[$(
    sql::query "SELECT file_id FROM finding WHERE user_id = ${user_id}
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
  sql::query "REPLACE INTO history (user_id, file_id, counter, last_used)
              VALUES (${user_id}, ${file_id}, 1, strftime('%s', 'now'))"
}

tg::start_bot "message,inline_query,chosen_inline_result" "start,help" "sticker"
