#!/usr/bin/env bash
set -e -u -o pipefail

find_replace() {
  sed -i "s/${1}/${2}/g" "${3}"
}
