const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const pool = {
  stakedToken: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
  rewardsToken: "0xbFa0841F7a90c4CE6643f651756EE340991F99D5",
  days: 5,
};

async function main() {
  await hardhat.run("compile");

  console.log("Deploying...");

  const Launchpool = await ethers.getContractFactory("BeefyLaunchpool");

  const durationInSec = 3600 * 24 * pool.days;

  const launchpool = await Launchpool.deploy(pool.stakedToken, pool.rewardsToken, durationInSec);
  await launchpool.deployed();

  console.log("Launchpool deployed to:", launchpool.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
