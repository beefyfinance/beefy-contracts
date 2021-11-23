const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  minDelay: 86400,
  proposers: ["0x3Eb7fB70C03eC4AEEC97C6C6C1B59B014600b7F7"],
  executors: ["0x3Eb7fB70C03eC4AEEC97C6C6C1B59B014600b7F7", "0x10aee6B5594942433e7Fc2783598c979B030eF3D"],
};

async function main() {
  await hardhat.run("compile");

  const TimelockController = await ethers.getContractFactory("TimelockController");

  const controller = await TimelockController.deploy(config.minDelay, config.proposers, config.executors);
  await controller.deployed();

  console.log(`Deployed to: ${controller.address}`);

  // await hardhat.run("verify:verify", {
  //   address: controller.address,
  //   constructorArguments: Object.values(config),
  // });
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
