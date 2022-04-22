#!/bin/sh
set -euf

mkdir -p /tmp/local-net

await() {
  command="${1}"
  exit_code="${2:-0}"
  timeout="${3:-2}"
  set +e
  while true; do
    eval "${command}"
    if [ $? -eq "${exit_code}" ]; then break; fi
    sleep "${timeout}"
  done
  set -e
}

signal_ready() {
  name="${1}"
  touch "build/.${name}-ready"
  # shellcheck disable=SC2064
  trap "rm -f build/.${name}-ready" INT
  while true; do sleep 100; done
}

await_ready() {
  name="${1}"
  await "test -f build/.${name}-ready"
}

docker_run() {
  name="${1}"
  shift
  # shellcheck disable=SC2064
  trap "docker stop ${name}" INT
  # shellcheck disable=SC2068
  docker run --rm -it --name "${name}" ${@}
}

github_clone() {
  path="${1}"
  tag="${2:-main}"
  if [ -d "build/${path}" ]; then return; fi
  git clone "git@github.com:${path}" "build/${path}"
  cd "build/${path}" && git checkout "${tag}" && cd -
}

find_replace_sed() {
  sed="sed"
  if [ "$(uname)" = Darwin ]; then sed=gsed; fi
  ${sed} -i "s/${1}/${2}/g" "${3}"
}

find_replace_jq() {
  updated=$(jq "${1} |= ${2}" "${3}")
  echo "${updated}" >"${3}"
}
