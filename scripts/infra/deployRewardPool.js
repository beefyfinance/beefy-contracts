const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  staked: "0xe6801928061CDbE32AC5AD0634427E140EFd05F9",
  rewards: "0x5C7F8A570d578ED84E63fdFA7b1eE72dEae1AE23",
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
