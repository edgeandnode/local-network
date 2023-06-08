import * as fs from "fs";
import * as mustache from "mustache";
import * as networkAddresses from "../../contracts/addresses.json";
import { Addresses } from "./addresses.template";

// mustache doesn't like numbered object keys
let renameAddresses: any = networkAddresses;
renameAddresses["hardhat"] = networkAddresses["1337"];

export let addresses: Addresses = {
  controller: "{{hardhat.Controller.address}}",
  graphToken: "{{hardhat.GraphToken.address}}",
  epochManager: "{{hardhat.EpochManager.address}}",
  disputeManager: "{{hardhat.DisputeManager.address}}",
  staking: "{{hardhat.Staking.address}}",
  curation: "{{hardhat.Curation.address}}",
  rewardsManager: "{{hardhat.RewardsManager.address}}",
  serviceRegistry: "{{hardhat.ServiceRegistry.address}}",
  gns: "{{hardhat.GNS.address}}",
  ens: "{{hardhat.IENS.address}}",
  ensPublicResolver: "{{hardhat.IPublicResolver.address}}",
  blockNumber: "",
  bridgeBlockNumber: "",
  network: "",
  tokenLockManager: "",
  subgraphNFT: "{{hardhat.SubgraphNFT.address}}",
  l1GraphTokenGateway: "{{hardhat.L1GraphTokenGateway.address}}",
  l2GraphTokenGateway: "",
  ethereumDIDRegistry: "{{hardhat.EthereumDIDRegistry.address}}",
  isL1: true,
};

const main = (): void => {
  try {
    let output = JSON.parse(
      mustache.render(JSON.stringify(addresses), renameAddresses),
    );
    output.blockNumber = "1"; // Hardcoded a few thousand blocks before 1st contract deployed
    output.bridgeBlockNumber = "1";
    output.network = "hardhat";
    output.useTokenLockManager = false;
    fs.writeFileSync(
      __dirname + "/generatedAddresses.json",
      JSON.stringify(output, null, 2),
    );
  } catch (e) {
    console.log(`Error saving artifacts: ${e.message}`);
  }
};

main();
