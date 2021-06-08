const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const pool = {
  stakedToken: "0x77276a7c9Ff3a6cbD334524d6F1f6219D039ac0E",
  rewardsToken: "0xfEcf784F48125ccb7d8855cdda7C5ED6b5024Cb3",
  days: 7,
};

async function main() {
  await hardhat.run("compile");

  const Launchpad = await ethers.getContractFactory("BeefyLaunchpool");

  console.log("Deploying...");

  const durationInSec = 3600 * 24 * pool.days;

  const launchpad = await Launchpad.deploy(pool.stakedToken, pool.rewardsToken, durationInSec);
  await launchpad.deployed();

  console.log("Launchpad pool deployed to:", launchpad.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
