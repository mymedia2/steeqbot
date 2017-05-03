#!/bin/bash
sqlite "$@" <<EOF

CREATE TABLE favorites (
    user_id NOT NULL
  , file_id NOT NULL
);
CREATE UNIQUE INDEX favorites_index
ON favorites (
    user_id
  , file_id
);

EOF
# vi: ft=sql
