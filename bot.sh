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

sleep 1
api_call getMe | jshon -e username -u

function process_message {
  local message=$(cat)
  local msg_text=$(echo "${message}" | jshon -e text -u)
  local msg_chat=$(echo "${message}" | jshon -e chat -e id)
  api_call sendMessage text="${msg_text}" chat_id="${msg_chat}" >/dev/null
}

last_update_id=0
while true; do
  updates=$(api_call getUpdates offset="${last_update_id}" timeout=100 \
    allowed_updates='["message","inline_query","chosen_inline_result"]')
  incoming_updates=$(echo "${updates}" | jshon -l)
  for (( i = 0; i < incoming_updates; i++ )); do
    current_update_id=$(echo "${updates}" | jshon -e $i -e update_id)
    (( last_update_id = current_update_id + 1 ))
    update_type=$(echo "${updates}" | jshon -e $i -k | grep -v update_id)
    echo "${updates}" | jshon -e $i -e "${update_type}" | "process_${update_type}"
  done
done
