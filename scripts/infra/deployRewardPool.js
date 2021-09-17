const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  staked: "0x6ab6d61428fde76768d7b45d8bfeec19c6ef91a8",
  rewards: "0xcf664087a5bb0237a0bad6742852ec6c8d69a27a",
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
