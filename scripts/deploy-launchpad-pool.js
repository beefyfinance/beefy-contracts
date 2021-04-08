const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");

const ethers = hardhat.ethers;

const pool = {
  stakedToken: "0x4d1A2b3119895d887b87509693338b86730bCE06",
  rewardsToken: "0xA25Dab5B75aC0E0738E58E49734295baD43d73F1",
  days: 5,
  capPerAddr: "10000000000000000000000000000000000",
};

async function main() {
  await hardhat.run("compile");

  const Launchpad = await ethers.getContractFactory("BeefyLaunchpadPool");

  console.log("Deploying...");

  const durationInSec = 3600 * 24 * pool.days;

  const launchpad = await Launchpad.deploy(pool.stakedToken, pool.rewardsToken, durationInSec, pool.capPerAddr);
  await launchpad.deployed();

  console.log("Launchpad pool deployed to:", launchpad.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
