const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const pool = {
  stakedToken: "0x1384Ed18E881C0CC9027DC04ab88bFBF641c6106",
  rewardsToken: "0x6261d793BdAe82842461A72B746bc18a5B7D2Bc4",
  days: 7,
};

async function main() {
  await hardhat.run("compile");

  const Launchpad = await ethers.getContractFactory("BeefyLaunchpool");

  console.log("Deploying...");

  const durationInSec = 3600 * 24 * pool.days;

  const launchpad = await Launchpad.deploy(pool.stakedToken, pool.rewardsToken, durationInSec, { gasLimit: 2000000 });
  await launchpad.deployed();

  console.log("Launchpad pool deployed to:", launchpad.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
