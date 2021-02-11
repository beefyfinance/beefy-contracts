const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");

const ethers = hardhat.ethers;

const pools = [
  {
    name: "TWT Pool",
    stakedToken: "0x4B0F1812e5Df2A09796481Ff14017e6005508003",
    rewardsToken: "",
    durationInSec: 604800,
    capPerAddr: "1000000000000000000000",
  },
];

async function main() {
  await hardhat.run("compile");

  const Launchpad = await ethers.getContractFactory("BeefyLaunchpadPool");

  for (pool of pools) {
    console.log("Deploying:", pool.name);

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
