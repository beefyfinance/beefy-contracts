const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");

const ethers = hardhat.ethers;

const config = {
  treasury: "0x4A32De8c248533C28904b24B4cFCFE18E9F2ad01",
  rewardPool: "0x453D4Ba9a2D594314DF88564248497F7D74d6b2C",
  unirouter: "0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F",
};

async function main() {
  await hardhat.run("compile");

  const [deployer] = await ethers.getSigners();

  const BeefyFeeBatch = await ethers.getContractFactory("BeefyFeeBatch");
  const batcher = await BeefyFeeBatch.deploy(config.treasury, config.rewardPool, config.unirouter, {
    gasPrice: 7000000000,
  });
  await batcher.deployed();

  console.log("Deployed to:", batcher.address);

  await registerSubsidy(batcher.address, deployer);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
