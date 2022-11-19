const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  staked: "0x5870700f1272a1AdbB87C3140bD770880a95e55D",
  rewards: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
  feeBatch: "0x3Cd5Ae887Ddf78c58c9C1a063EB343F942DbbcE8"
};

async function main() {
  await hardhat.run("compile");

  const Pool = await ethers.getContractFactory("BeefyRewardPool");
  const pool = await Pool.deploy(config.staked, config.rewards);
  await pool.deployed();

  

  console.log("Reward pool deployed to:", pool.address);

//  console.log(`Transfering Ownership....`);
//  await pool.transferOwnership(config.feeBatch);

  console.log(`Verifying contract....`);
  await hardhat.run("verify:verify", {
    address: pool.address,
    constructorArguments: [
    config.staked,
    config.rewards,
    ],
  })
}


main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });