const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");

const ethers = hardhat.ethers;

const pools = [
  {
    stakedToken: "0xb35Dc0b5eFd7c75590a9da55BE46d968c5804e24",
    rewardsToken: "0x9768E5b2d8e761905BC81Dfc554f9437A46CdCC6",
    days: 5,
    capPerAddr: "10000000000000000000000000000000000",
  },
];

async function main() {
  await hardhat.run("compile");

  const Launchpad = await ethers.getContractFactory("BeefyLaunchpadPool");

  for (pool of pools) {
    console.log("Deploying...");

    const [deployer] = await ethers.getSigners();

    const durationInSec = 3600 * 24 * pool.days;

    const launchpad = await Launchpad.deploy(pool.stakedToken, pool.rewardsToken, durationInSec, pool.capPerAddr);
    await launchpad.deployed();

    console.log("Launchpad pool deployed to:", launchpad.address);

    await registerSubsidy(launchpad.address, deployer);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
