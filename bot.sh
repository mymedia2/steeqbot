#!/bin/bash

set -o errexit pipefail
source api.sh

function process_message {
  local message=$(cat)
  local msg_text=$(echo "${message}" | jshon -e text -u)
  local msg_chat=$(echo "${message}" | jshon -e chat -e id)
  tg::api_call sendMessage text="${msg_text}" chat_id="${msg_chat}" >/dev/null
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

tg::start_bot "message,inline_query,chosen_inline_result" "start,list" "sticker"
