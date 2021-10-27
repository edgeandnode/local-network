#!/usr/bin/env bash
source prelude.bash

cd projects/graphprotocol/contracts

ADDRESS_BOOK=addresses.json
CONTROLLER_CONTRACT_ADDRESS=$(jq '."1337".Controller.address' "${ADDRESS_BOOK}")
EPOCHMANAGER_CONTRACT_ADDRESS=$(jq '."1337".EpochManager.address' "${ADDRESS_BOOK}")
GRAPHTOKEN_CONTRACT_ADDRESS=$(jq '."1337".GraphToken.address' "${ADDRESS_BOOK}")
SERVICEREGISTRY_CONTRACT_ADDRESS=$(jq '."1337".GNS.address' "${ADDRESS_BOOK}")
CURATION_CONTRACT_ADDRESS=$(jq '."1337".Curation.address' "${ADDRESS_BOOK}")
GNS_CONTRACT_ADDRESS=$(jq '."1337".GNS.address' "${ADDRESS_BOOK}")
STAKING_CONTRACT_ADDRESS=$(jq '."1337".Staking.address' "${ADDRESS_BOOK}")
REWARDSMANAGER_CONTRACT_ADDRESS=$(jq '."1337".RewardsManager.address' "${ADDRESS_BOOK}")
DISPUTEMANAGER_CONTRACT_ADDRESS=$(jq '."1337".DisputeManager.address' "${ADDRESS_BOOK}")
ETHEREUMDIDREGISTRY_CONTRACT_ADDRESS=$(jq '."1337".EthereumDIDRegistry.address' "${ADDRESS_BOOK}")

contracts="\
  ${CONTROLLER_CONTRACT_ADDRESS} \
  ${EPOCHMANAGER_CONTRACT_ADDRESS} \
  ${GRAPHTOKEN_CONTRACT_ADDRESS} \
  ${SERVICEREGISTRY_CONTRACT_ADDRESS} \
  ${CURATION_CONTRACT_ADDRESS} \
  ${GNS_CONTRACT_ADDRESS} \
  ${STAKING_CONTRACT_ADDRESS} \
  ${REWARDSMANAGER_CONTRACT_ADDRESS} \
  ${DISPUTEMANAGER_CONTRACT_ADDRESS} \
  ${ETHEREUMDIDREGISTRY_CONTRACT_ADDRESS} \
"
contracts_not_found=0

for contract in ${contracts}; do
  [[ $(curl "${ETHEREUM}" \
    -s \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\": [${contract}, \"latest\"],\"id\":1}" \
    | jq '.result == null' || '.result == 0x0') ]] \
    || { echo >&2 "Contract ${contract} not deployed"; ((contracts_not_found=contracts_not_found+1)); }
done

if [ "${contracts_not_found}" -gt 0 ]; then
  echo "${contracts_not_found} contracts not found, exiting.."
  exit 1
else
  echo "All contracts were successfully deployed!"
fi
