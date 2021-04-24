const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  minDelay: 21600,
  proposers: ["0x4e3227c0b032161Dd6D780E191A590D917998Dc7"],
  executors: ["0x4e3227c0b032161Dd6D780E191A590D917998Dc7", "0xd529b1894491a0a26B18939274ae8ede93E81dbA"],
};

async function main() {
  await hardhat.run("compile");

  const TimelockController = await ethers.getContractFactory("TimelockController");

  const controller = await TimelockController.deploy(config.delay, config.proposers, config.executors);
  await controller.deployed();

  console.log(`Deployed to: ${controller.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
