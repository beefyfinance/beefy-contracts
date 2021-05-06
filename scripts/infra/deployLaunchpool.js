const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const pool = {
  stakedToken: "0xf2064C230b285AA6Cf45c6267DA86a8E3505D0AA",
  rewardsToken: "0x95111f630ac215eb74599ed42c67e2c2790d69e2",
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
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
