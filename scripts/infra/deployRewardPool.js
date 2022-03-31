const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  staked: "0xCa3F508B8e4Dd382eE878A314789373D80A5190A",
  rewards: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
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
