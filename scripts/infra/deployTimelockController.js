const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  minDelay: 86400,
  proposers: ["0x4E2a43a0Bf6480ee8359b7eAE244A9fBe9862Cdf"],
  executors: ["0x4E2a43a0Bf6480ee8359b7eAE244A9fBe9862Cdf", "0x10aee6B5594942433e7Fc2783598c979B030eF3D"],
};

async function main() {
  await hardhat.run("compile");

  const TimelockController = await ethers.getContractFactory("TimelockController");

  const controller = await TimelockController.deploy(config.minDelay, config.proposers, config.executors);
  await controller.deployed();

  console.log(`Deployed to: ${controller.address}`);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
