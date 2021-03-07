const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");

const ethers = hardhat.ethers;

const abi = ["function notifyRewards() external"];

const pools = [
  {
    name: "Soups Pool",
    stakedToken: "0xF3C1EB01E40c47fd32D0397e56569809aae0e9c7",
    rewardsToken: "0x69F27E70E820197A6e495219D9aC34C8C6dA7EeE",
    durationInSec: 432000,
    capPerAddr: "10000000000000000000000000000000",
  },
];

async function main() {
  await hardhat.run("compile");

  const Launchpad = await ethers.getContractFactory("BeefyLaunchpadPool");

  for (pool of pools) {
    console.log("Deploying:", pool.name);

    const [deployer] = await ethers.getSigners();

    const launchpad = await Launchpad.deploy(pool.stakedToken, pool.rewardsToken, pool.durationInSec, pool.capPerAddr);
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
