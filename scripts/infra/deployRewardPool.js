const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  staked: "0x1F2A8034f444dc55F963fb5925A9b6eb744EeE2c",
  rewards: "0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd",
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
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
