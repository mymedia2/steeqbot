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

# Модуль для более простого написания ботов для Telegram. Определено несколько
# публичных функций: tg::api_call, tg::emit_call, tg::route_update, ... . Для
# работы должна быть установлена переменная окружения BOT_TOKEN.

set -o errexit -o pipefail

# Вызывает метод Telegram Bot API.
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
  local url="https://api.telegram.org/bot${BOT_TOKEN}/$1"
  declare -a params

  for par in "${@:2}"; do
    params+=("--data-urlencode" "${par}")
  done

  local data=$(curl --silent --show-error "${url}" "${params[@]}")

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

# Отправляет запрос к телеграм, посредством CGI. Команды этого протокола просто
# печатаются на stdout, чтобы их обработал веб-сервер. Вызвать функцию следует
# не более одного раза.
#
# Параметры:
#   $1   ~ имя метода, обязательный
#   ост. ~ последовательность аргументов вида 'имя=значение'
#
# Интерфейс этой функции аналогичен как у tg::api_call за тем исключением, что
# результат не печатается, т.к. Telegram попросту не возвращает его.
#
function tg::emit_call {
  declare -a params
  for par in "=$1" "${@:2}"; do
    local name="${par/=*}"
    local value="${par/*=}"
    params+=(-s "${value}" -i "${name:-method}")
  done
  echo -e "Content-Type: application/json\n"
  jshon -Q -n object "${params[@]}"
}

# Читает обновление со стандартного входа и вызывает функцию с названием вида
# process_* в соответствии с принятым типом сообщения и заданными параметрами.
# Каждой функции на стандартный ввод подаётся запрашиваемый объект обновления,
# причём одно сообщение обрабатывается только единожды. Кроме того, эта функция
# выводит некоторые заголовки CGI для упрощения реализации. Каждая из функций
# обратного вызова может дописать свои заголовки и вывести результат работы --
# запрос к Telegram API.
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
function tg::route_update {
  local supported_updates_types="${1:-messages}"
  local supported_commands_list="$2"
  local supported_message_types="$3"

  # вывод первого заголовка на случай, если не будет отправлено никаких запросов
  echo "Status: 200"

  local update=$(cat)
  local incoming=$(echo "${update}" | jshon -k | grep -v update_id)
  if echo "${incoming}" | egrep -q "${supported_updates_types//,/|}"; then
    local cInput=$(echo "${update}" \
      | jshon -Q -e message -e text -u \
      | sed -rnz '\!^/'"${supported_commands_list//,/|}"'\>!{s,/(\w*).*,\1,;p}')
    local content_type=$(echo "${update}" \
      | jshon -Q -e message -k \
      | egrep "${supported_message_types//,/|}")

    if [ -n "${cInput}" ]; then  # обработка команд
      local function_name="process_${cInput}_command"
    elif echo "${update}" \
        | jshon -Q -e message -e reply_to_message >/dev/null &&
        [[ "$3" =~ "reply" ]]; then  # обработка ответов
      local function_name="process_reply"
    elif [ -n "${content_type}" ]; then  # обработка сообщений по типу
      local function_name="process_${content_type}"
    else  # обработка прочих обновлений
      local function_name="process_${incoming}"
    fi

    # функция вызыывается только если он объявлена
    # TODO: подумать над лучшим решением
    if compgen -A function | grep -q "${function_name}"; then
      echo "${update}" | jshon -e "${incoming}" | "${function_name}"
    fi
  fi

  # завершение вывода CGI заголовков; если был отправлен запрос, это не помешает
  echo
}

# Устанавливает webhook для приёма входящих обновлений. Завершает работу
# сценария, если сервер недоступен.
#
# Параметры:
#   $1 ~ Допустимые обновления через запятую
#   $2 ~ Адрес домена где расположен бот
#   $3 ~ Защитная часть URL, добавляется в конец
#
function tg::initialize_webhook {
  local updates="$1"
  local domain="$2"
  local hash="$3"

  local address="https://${domain}/webhook/${hash}"
  local updates_json="[\"${updates//,/\",\"}\"]"

  if curl --silent --show-error "${address}" | grep -q "steeqbot works"; then
    tg::api_call setWebhook url="${address}" allowed_updates="${updates_json}" \
      >/dev/null
  else
    echo "Проблемы с веб-сервером: ${address}" >&2
    exit 1
  fi
}

if [ -z "${BOT_TOKEN}" ]; then
  echo "Не задан ключ доступа к Telegram API" >&2
  exit 1
fi
