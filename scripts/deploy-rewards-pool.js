const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  staked: "0x765277eebeca2e31912c9946eae1021199b39c61",
  rewards: "0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F",
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
