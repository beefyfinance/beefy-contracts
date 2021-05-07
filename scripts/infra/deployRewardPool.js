const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  staked: "0xFbdd194376de19a88118e84E279b977f165d01b8",
  rewards: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270",
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
