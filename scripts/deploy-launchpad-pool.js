const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");

const ethers = hardhat.ethers;

const abi = ["function notifyRewards() external"];

const pools = [
  {
    name: "SALT Pool",
    stakedToken: "0xe0B473c0dD6D7Fea5B395c3Ce7ffd4FEF0ab4373",
    rewardsToken: "0x2849b1aE7E04A3D9Bc288673A92477CF63F28aF4",
    durationInSec: 432000,
    capPerAddr: "1000000000000000000000000000000",
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
