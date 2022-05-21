const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  staked: "0x97bfa4b212A153E15dCafb799e733bc7d1b70E72",
  rewards: "0x580A84C73811E1839F75d86d75d88cCa0c241fF4",
};

async function main() {
  await hardhat.run("compile");

  const Pool = await ethers.getContractFactory("BeefyRewardPool");
  const pool = await Pool.deploy(config.staked, config.rewards);
  await pool.deployed();

  console.log("Reward pool deployed to:", pool.address);

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