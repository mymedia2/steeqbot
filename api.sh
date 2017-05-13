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

# Модуль для более простого написания ботов для Telegram. Определены две
# публичные фукнции: tg::api_call и tg::start_bot. Для работы должна быть
# установлена переменная окружения BOT_TOKEN.

set -o errexit pipefail

# Внутренние объекты для реализации постоянного соединения.
_tg_socket_file="/var/tmp/$0.socket"
coproc _tg_tls_service {
  while true; do
    openssl s_client -quiet -connect "api.telegram.org:443" \
      -servername "api.telegram.org" 2>/dev/null
  done
}
coproc _tg_socket_proxy {
  while true; do
    nc -lU "${_tg_socket_file}" <&${_tg_tls_service[0]} >&${_tg_tls_service[1]}
  done
}

# Вызывает метод Telegram API, используя уже установленное постоянное
# HTTPS-соединение с сервером.
#
# Параметры:
#   $1   ~ имя метода, обязательный
#   ост. ~ последовательность аргументов вида 'имя=значение'
#
# Результат в формате JSON печатается на стандартный вывод. В случае ошибки
# возвращается её код. При непустой переменной DEBUG в поток ошибок выводятся
# диагностические сообщения.
#
# Пример:
#   tg::api_call sendMessage text="Hello world!" chat_id=42 >/dev/null
#
function tg::api_call {
  local url="http://api.telegram.org/bot${BOT_TOKEN}/$1"
  declare -a params

  for par in "${@:2}"; do
    params+=("--data-urlencode" "${par}")
  done

  local data=$(curl --unix-socket "${_tg_socket_file}" --silent --show-error \
    "${url}" "${params[@]}")

  local status=$(echo "${data}" | jshon -e ok)
  if [ "${status}" = "true" ]; then
    echo "${data}" | jshon -e result
  elif [ -n "${DEBUG}" ]; then
    local code=$(echo "${data}" | jshon -e error_code)
    local desc=$(echo "${data}" | jshon -e description -u)
    echo "Error ${code}: ${desc}" >&2
    return "${code}"
  fi
}

# Запускает обработку входящих сообщений. Вызывает функции с названием вида
# process_* в соответствии с принятым типом сообщения и заданными параметрами.
# Всем функциям на стандартный ввод подаётся запрашиваемый объект обновления.
# Каждое сообщение обрабатывается лишь единожды. Управление не возвращается.
#
# Параметры:
#   $1 ~ Список обрабатываемых типов обновлений через запятую. Возможные типы:
#        message, edited_message, channel_post, edited_channel_post,
#        inline_query, chosen_inline_result, callback_query. При поступлении
#        входящего обновления указанного типа вызывается функция process_тип.
#        Необязательный, значение по умолчанию = messages.
#   $2 ~ Список обрабатываемых команд бота через запятую. При поступлении
#        указанной входящей команды вызывается функция process_название_command.
#        Необязательный, приоритетнее $1.
#   $3 ~ Список обрабатываемых типов сообщений через запятую. Возможные типы:
#        text, audio, document, game, photo, sticker, video, voice, contact,
#        location, venue, reply, service (пока не реализовано). При получении
#        указанного сообщения вызывается функция process_тип.
#
function tg::start_bot {
  local supported_updates_types=$(echo "${1:-messages}" \
    | sed 's/^\s*/["/;s/\s*,\s*/","/g;s/\s*$/"]/')
  local supported_commands_list=$(echo "$2" \
    | sed 's/^\s*/(/;s/\s*,\s*/|/g;s/\s*$/)/')
  local supported_message_types=$(echo "$3" \
    | sed 's/^\s*/^(/;s/\s*,\s*/|/g;s/\s*$/)$/')
  sleep 1

  local next_update_id=0
  while true; do
    local updates=$(tg::api_call getUpdates offset="${next_update_id}" \
      timeout=100 allowed_updates="${supported_updates_types}")
    local incoming_updates=$(echo "${updates}" | jshon -l)
    for (( i = 0; i < incoming_updates; i++ )); do
      local cInput=$(echo "${updates}" \
        | jshon -Q -e $i -e message -e text -u \
        | sed -rnz '\!^/\<'"${supported_commands_list}"'\>!{s,/(\w*).*,\1,;p}')
      local content_type=$(echo "${updates}" \
        | jshon -Q -e $i -e message -k \
        | egrep "${supported_message_types}")
      local incoming=$(echo "${updates}" | jshon -e $i -k | grep -v update_id)

      if [ -n "${cInput}" ]; then  # обработка команд
        local function_name="process_${cInput}_command"
      elif echo "${updates}" \
          | jshon -Q -e $i -e message -e reply_to_message >/dev/null &&
          [[ "$3" =~ "reply" ]]; then  # обработка ответов
        local function_name="process_reply"
      elif [ -n "${content_type}" ]; then  # обработка сообщений по типу
        local function_name="process_${content_type}"
      else  # обработка прочих обновлений
        local function_name="process_${incoming}"
      fi
      echo "${updates}" | jshon -e $i -e "${incoming}" | "${function_name}"
      let next_update_id=$(echo "${updates}" | jshon -e $i -e update_id)+1
    done
  done
}

if [ -z "${BOT_TOKEN}" ]; then
  echo "Не задан ключ доступа к Telegram API" >&2
  exit 1
fi
