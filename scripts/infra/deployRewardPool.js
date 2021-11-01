const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  staked: "0x639a647fbe20b6c8ac19e48e2de44ea792c62c5c",
  rewards: "0x471EcE3750Da237f93B8E339c536989b8978a438",
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
