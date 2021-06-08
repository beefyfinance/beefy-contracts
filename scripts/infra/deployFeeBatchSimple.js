const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  treasury: "0xA3e3Af161943CfB3941B631676134bb048739727",
  rewardPool: "0x86d38c6b6313c5A3021D68D1F57CF5e69197592A",
  wNative: "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7",
};

async function main() {
  await hardhat.run("compile");

  const BeefyFeeBatchSimple = await ethers.getContractFactory("BeefyFeeBatchSimple");
  const batcher = await BeefyFeeBatchSimple.deploy(config.treasury, config.rewardPool, config.wNative);
  await batcher.deployed();

  console.log("Deployed to:", batcher.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
