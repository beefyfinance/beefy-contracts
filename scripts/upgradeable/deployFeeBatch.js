const hardhat = require("hardhat");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");
const { addressBook } = require("blockchain-addressbook");

const ethers = hardhat.ethers;

const config = {
  bifi: "0xFbdd194376de19a88118e84E279b977f165d01b8",
  wNative: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
  treasury: "0xc3a4fdcba79DB04b4C3e352b1C467B3Ba909D84A",
  rewardPool: "0x48F4634c8383aF01BF71AefBC125eb582eb3C74D",
  unirouter: "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff",
};

async function main() {
  await hardhat.run("compile");

  const [signer] = await ethers.getSigners();
  const provider = signer.provider;

  const BeefyFeeBatch = await ethers.getContractFactory("BeefyFeeBatchV2");
  const batcher = await upgrades.deployProxy(BeefyFeeBatch, [
    config.bifi,
    config.wNative,
    config.treasury,
    config.rewardPool,
    config.unirouter,
  ]);

  await batcher.deployed();

  const implementationAddr = await getImplementationAddress(provider, batcher.address);

  console.log(`Deployed proxy at ${batcher.address}`);
  console.log(`Deployed implementation at ${implementationAddr}`);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
