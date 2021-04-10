#!/bin/bash
#
# Поисковик стикеров в Telegram
# Copyright (c) Гурьев Николай, 2017
#
# Эта программа является свободным программным обеспечением: Вы можете
# распространять её и (или) изменять, соблюдая условия Генеральной публичной
# лицензии GNU Affero, опубликованной Фондом свободного программного
# обеспечения; либо редакции 3 Лицензии, либо (на Ваше усмотрение) любой
# редакции, выпущенной позже.
#
# Эта программа распространяется в расчёте на то, что она окажется полезной, но
# БЕЗ КАКИХ-ЛИБО ГАРАНТИЙ, включая подразумеваемую гарантию КАЧЕСТВА либо
# ПРИГОДНОСТИ ДЛЯ ОПРЕДЕЛЕННЫХ ЦЕЛЕЙ.
#
# Ознакомьтесь с Генеральной публичной лицензией GNU Affero для получения более
# подробной информации. Вы должны были получить копию Генеральной публичной
# лицензии GNU Affero вместе с этой программой. Если Вы ее не получили, то
# перейдите по адресу: <https://www.gnu.org/licenses/agpl.html>.

# Точка входа для бота. Запускать этот файл. Подробнее в README.

set -o errexit -o pipefail
source api.sh
source database.sh

function process_start_command {
  local chat
  chat=$(jshon -e chat -e id)
  local msg="\
Привет! Я могу помочь найти тебе подходящий стикер именно в тот момент, когда \
он очень нужен. Чтобы вызвать меня, просто набери моё имя в строке сообщения, \
а затем введи cвой запрос."
  local kbd='{"inline_keyboard":[[
    {"text":"↪️ Опробовать...","switch_inline_query":""} ]]}'
  tg::emit_call sendMessage text="${msg}" chat_id="${chat}" \
    reply_markup="${kbd}"
}

function process_help_command {
  local chat
  chat=$(jshon -e from -e id)
  local msg="\
Я – бот-помощник в поиске стикеров. Просто напиши мне, какой стикер тебя \
интересует, и я попытаюсь найти его. Но помни, пока мне известно очень мало \
стикеров, поэтому поиск может быть нерезультативным. Если тебя расстраивает \
эта ситуация, отправь мне в личку свои любимые стикеры, и со временем я их \
проиндексирую.
Кроме того, я представляю из себя свободное ПО, и мой код доступен на условиях \
GNU/AGPL github.com/mymedia2/steeqbot"
  tg::emit_call sendMessage text="${msg}" chat_id="${chat}"
}

function process_sticker {
  local message user_id file_id
  message=$(cat)
  user_id=$(jshon -e from -e id <<< "${message}")
  file_id=$(jshon -e sticker -e file_id <<< "${message}")
  if jshon -e chat -e type <<< "${message}" | grep -q private; then
    if sql::query "SELECT count(*) FROM history WHERE file_id = ${file_id}" \
        | grep -q 0; then
      if (( RANDOM % 2 )); then
        local msg="Ого, какой интересный стикер!"
      else
        local msg="Ого, какой красивый стикер!"
      fi
      if (( RANDOM % 2 )); then
        msg+=" А что на нём изображено?"
      else
        msg+=" А что тут изображено?"
      fi
    else
      local msg="О! А этот стикер я уже знаю 😃"
    fi
    tg::emit_call sendMessage text="${msg}" chat_id="${user_id}" \
      reply_markup='{"force_reply":true}'
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
  local update query_id user_id pattern stickers_json
  update=$(cat)
  query_id=$(jshon -e id -u <<< "${update}")
  user_id=$(jshon -e from -e id <<< "${update}")
  pattern=$(jshon -e query -u <<< "${update}" | sed 's/"/""/g')
  stickers_json=[$(sql::query "
    WITH r AS (SELECT *, user_id != ${user_id} AS owner_flag, 1 AS category
               FROM history WHERE words LIKE \"%${pattern,,}%\"
               ORDER BY owner_flag DESC, sendings_tally DESC),
         m AS (SELECT *, 0 AS category FROM history
               WHERE file_id NOT IN (SELECT file_id FROM history WHERE words != '')
                 AND $(sql::to_literal <<< "${pattern}") != ''
               ORDER BY sendings_tally DESC
               LIMIT (SELECT count(*) FROM r) / 3)
    SELECT DISTINCT file_id FROM r UNION ALL SELECT DISTINCT file_id FROM m
    LIMIT 50" \
      | sed -E 's/(.{,64}).*/{"type":"sticker","id":"\1","sticker_file_id":"\0"}/
                2~1s/.*/,\0/')]
  tg::emit_call answerInlineQuery inline_query_id="${query_id}" \
    results="${stickers_json}" cache_time=600 is_personal=true
}

function process_chosen_inline_result {
  local result user_id file_id words
  result=$(cat)
  file_id=$(jshon -e result_id <<< "${result}")
  user_id=$(jshon -e from -e id <<< "${result}")
  words=$(jshon -e query -u  <<< "${result}" | sql::to_literal)
  sql::query "INSERT INTO history (user_id, file_id, words)
              VALUES (${user_id}, ${file_id}, ${words,,})"
}

function process_text {
  local query user_id file_id pattern
  query=$(cat)
  jshon -e chat -e type <<< "${query}" | grep -q private || return 0
  user_id=$(jshon -e from -e id <<< "${query}")
  pattern=$(jshon -e text -u <<< "${query}" | sed "s/\"/\"\"/g;s/'/''/g")
  file_id=$(sql::query "
    SELECT file_id FROM history WHERE words LIKE \"%${pattern,,}%\"
    ORDER BY user_id != ${user_id}, sendings_tally DESC LIMIT 1")
  if [ -z "${file_id}" ]; then
    tg::emit_call sendMessage chat_id="${user_id}" \
      text="К сожалению, по этому запросу ничего не нашлось 😔"
  else
    tg::emit_call sendSticker chat_id="${user_id}" sticker="${file_id}"
  fi
}

function process_reply {
  local data user_id file_id description
  data=$(cat)
  jshon -e chat -e type <<< "${data}" | grep -q private || return 0
  user_id=$(jshon -e from -e id <<< "${data}")
  description=$(jshon -e text <<< "${data}" || true)
  file_id=$(jshon -Q -e reply_to_message -e sticker -e file_id <<< "${data}" \
    || true)
  if [ -n "${description}" ]; then
    local res=true
    if [ -n "${file_id}" ]; then
      sql::query "
        INSERT INTO history (user_id, file_id, words, sendings_tally)
        VALUES (${user_id}, ${file_id}, ${description,,}, 0)"
    else
      sql::query "
        INSERT INTO history (user_id, words, sendings_tally, file_id)
        VALUES (${user_id}, ${description,,}, 0,
        (SELECT file_id FROM states WHERE user_id = ${user_id}))" || res=false
    fi
    if [ "${res}" = true ]; then
      tg::emit_call sendMessage text="Понятно 🙂" chat_id="${user_id}"
    fi
  fi
}

valid_updates="message,inline_query,chosen_inline_result"
if [ "$1" = "--set-webhook" ]; then
  tg::initialize_webhook "${valid_updates}" "$2" "$3"
elif [ "${REQUEST_METHOD}" != GET ]; then
  tg::route_update "${valid_updates}" "start,help" "text,sticker,reply"
else
  # проверка работоспособности
  echo -e "Content-Type: text/plain\n"
  echo -n "steeqbot works"
fi
