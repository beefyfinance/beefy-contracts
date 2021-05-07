const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const pool = {
  stakedToken: "0xD411121C948Cff739857513E1ADF25ED448623f8",
  rewardsToken: "0x8d112fcdf377a2c4cb41b60aae32199f939a866c",
  days: 6,
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
