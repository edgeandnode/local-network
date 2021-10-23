#!/usr/bin/env bash
set -e -u -o pipefail

find_replace_sed() {
  sed -i "s/${1}/${2}/g" "${3}"
}

find_replace_jq() {
  updated=$(jq "${1} |= ${2}" "${3}")
  echo "${updated}" >"${3}"
}
