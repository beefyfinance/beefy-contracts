const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");

const ethers = hardhat.ethers;

const pools = [
  {
    name: "Astronaut Pool",
    stakedToken: "0x5B06aA1ebd2e15bC6001076355E5B4C39Cbc83F3",
    rewardsToken: "0x05B339B0A346bF01f851ddE47a5d485c34FE220c",
    durationInSec: 604800,
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
