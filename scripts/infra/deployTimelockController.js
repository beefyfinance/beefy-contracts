const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  minDelay: 86400,
  proposers: ["0x04db327e5d9A0c680622E2025B5Be7357fC757f0"],
  executors: ["0x04db327e5d9A0c680622E2025B5Be7357fC757f0", "0x4fED5491693007f0CD49f4614FFC38Ab6A04B619"],
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
