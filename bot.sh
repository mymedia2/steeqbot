#!/bin/bash

# N.B.: должна быть установлена переменная окружения BOT_TOKEN

set -o errexit pipefail

socket_file="/var/tmp/$0.socket"
coproc tls_service {
  while true; do
    openssl s_client -quiet -connect api.telegram.org:443 \
      -servername api.telegram.org 2>/dev/null
  done
}
coproc socket_proxy {
  while true; do
    nc -lU "${socket_file}" <&${tls_service[0]} >&${tls_service[1]}
  done
}

function api_call {
  local url="http://api.telegram.org/bot${BOT_TOKEN}/$1"
  declare -a params

  for par in "${@:2}"; do
    params+=("--data-urlencode" "${par}")
  done

  local data=$(curl --unix-socket "${socket_file}" -sS "${url}" "${params[@]}")
  local status=$(echo "${data}" | jshon -e ok)
  if [ "${status}" = "true" ]; then
    echo "${data}" | jshon -e result
  elif [ -z "${NO_ERROR}" ]; then
    local code=$(echo "${data}" | jshon -e error_code)
    local desc=$(echo "${data}" | jshon -e description -u)
    echo "Error ${code}: ${desc}" >&2
    return "${code}"
  fi
}

function process_message {
  local message=$(cat)
  local msg_text=$(echo "${message}" | jshon -e text -u)
  local msg_chat=$(echo "${message}" | jshon -e chat -e id)
  api_call sendMessage text="${msg_text}" chat_id="${msg_chat}" >/dev/null
}

function process_inline_query {
  echo inline query
  cat
}

function process_start_command {
  echo start command
  cat
}

function process_list_command {
  echo list command
  cat
}

function process_sticker {
  echo new sticker
  cat
}

function start_bot {
  local supported_updates_types=$(echo "${1:-messages}" \
    | sed 's/^\s*/["/;s/\s*,\s*/","/g;s/\s*$/"]/')
  local supported_commands_list=$(echo "$2" \
    | sed 's/^\s*/\\(/;s/\s*,\s*/\\|/g;s/\s*$/\\)/')
  local supported_message_types=$(echo "$3" \
    | sed 's/^\s*/\\(/;s/\s*,\s*/\\|/g;s/\s*$/\\)/')
  sleep 1

  local last_update_id=0
  while true; do
    local updates=$(api_call getUpdates offset="${last_update_id}" timeout=100 \
      allowed_updates="${supported_updates_types}")
    local incoming_updates=$(echo "${updates}" | jshon -l)
    for (( i = 0; i < incoming_updates; i++ )); do
      local current_update_id=$(echo "${updates}" | jshon -e $i -e update_id)
      (( last_update_id = current_update_id + 1 ))

      # Обработка команд
      if echo "${updates}" \
        | jshon -Q -e $i -e message -e text -u \
        | grep -q "^/${supported_commands_list}"; then
        local cmd=$(echo "${updates}" \
          | jshon -e $i -e message -e text -u \
          | sed 's,/'"${supported_commands_list}"',\1,')
        echo "${updates}" | jshon -e $i -e message | "process_${cmd}_command"
        continue
      fi

      # Обработка сообщений по типу
      local content_type=$(echo "${updates}" \
        | jshon -Q -e $i -e message -k \
        | grep "${supported_message_types}")
      if [ -n "${content_type}" ]; then
        echo "${updates}" | jshon -e $i -e message | "process_${content_type}"
        continue
      fi

      # Обработка прочих обновлений
      local incoming=$(echo "${updates}" | jshon -e $i -k | grep -v update_id)
      echo "${updates}" | jshon -e $i -e "${incoming}" | "process_${incoming}"
    done
  done
}
start_bot "message,inline_query,chosen_inline_result" "start,list" "sticker"
