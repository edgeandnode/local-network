#!/usr/bin/env bash
source prelude.bash

repos="\
  graphprotocol/common-ts
  graphprotocol/contracts"

for repo in ${repos}; do
  if [ -d "projects/${repo}" ]; then continue; fi
  git clone "git@github.com:${repo}" "projects/${repo}"
done
