import "@nomiclabs/hardhat-ethers";
import { ethers, network } from "hardhat";

async function main() {
  const dataEdgeAddress = process.env.DATA_EDGE_CONTRACT_ADDRESS!;
  const [signer] = await ethers.getSigners();

  // RegisterNetworks message: add network eip155:1337 (same as protocol chain)
  // This is necessary because since commit #cc729541e5d3fe0a11ef7f9a4382dd693525eb9e the Epoch
  // Block Oracle won't send the RegisterNetworks message.
  // [{ "add": ["eip155:1337"], "message": "RegisterNetworks", "remove": [] }]
  // See https://graphprotocol.github.io/block-oracle/
  const txHash = await network.provider.send("eth_sendTransaction", [
    {
      from: signer.address,
      to: dataEdgeAddress,
      data: "0xa1dce3320000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000f030103176569703135353a313333370000000000000000000000000000000000",
    },
  ]);
  await network.provider.send("evm_mine", []);
  const tx = await network.provider.send("eth_getTransactionByHash", [txHash]);
  const blockNumber = ethers.BigNumber.from(tx.blockNumber);
  console.log(JSON.stringify({ blockNumber: blockNumber.toNumber() }));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
