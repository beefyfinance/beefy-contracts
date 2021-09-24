const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  treasury: "0x09EF0e7b555599A9F810789FfF68Db8DBF4c51a0",
  rewardPool: "0xDeB0a777ba6f59C78c654B8c92F80238c8002DD2",
  unirouter: "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff",
  bifi: "0xFbdd194376de19a88118e84E279b977f165d01b8",
  wNative: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
};

async function main() {
  await hardhat.run("compile");

  const BeefyFeeBatch = await ethers.getContractFactory("BeefyFeeBatchV2");
  const batcher = await upgrades.deployProxy(BeefyFeeBatch, [
    config.bifi,
    config.wNative,
    config.treasury,
    config.rewardPool,
    config.unirouter,
  ]);

  await batcher.deployed();

  console.log("deployed", batcher.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
