const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  staked: "0xd6070ae98b8069de6B494332d1A1a81B6179D960",
  rewards: "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7",
};

async function main() {
  await hardhat.run("compile");

  const Pool = await ethers.getContractFactory("BeefyRewardPool");
  const pool = await Pool.deploy(config.staked, config.rewards);
  await pool.deployed();

  console.log("Reward pool deployed to:", pool.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
