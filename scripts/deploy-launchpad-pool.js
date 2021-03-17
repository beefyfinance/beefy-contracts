const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");

const ethers = hardhat.ethers;

const pools = [
  {
    name: "NUTS Pool",
    stakedToken: "0x3B5332A476AbCdb80Cde6645e9e5563435e97772",
    rewardsToken: "0x8893D5fA71389673C5c4b9b3cb4EE1ba71207556",
    durationInSec: 432000,
    capPerAddr: "10000000000000000000000000000000000",
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
