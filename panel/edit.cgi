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

# Позволяет изменять описания к стикерам

set -o errexit pipefail
source ../database.sh

file_id=$(echo "${QUERY_STRING}" | sed 's/^file_id=//')
tags=$(sed 's/^tags=//;s/\r$//' | LANG=ru_RU.UTF-8 egrep -o '(\w|[-+!?№#@ ])+' \
  | sed "s/.*/('${file_id}','\\0')/;2~1s/^/,/")

# TODO: подумать о транзакции
sql::query "DELETE FROM stickers WHERE file_id = '${file_id}';
  INSERT INTO stickers (file_id, description) VALUES ${tags}"

if [ "${HTTP_X_REQUESTED_WITH}" != XMLHttpRequest ]; then
  echo -e "Status: 303\nLocation: ${HTTP_REFERER}"
fi
echo -e "Content-Type: text/plain\n"
echo -n "ok"

# vi: ft=sh
