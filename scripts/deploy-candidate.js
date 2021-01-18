const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  vault: "0x8AE31751A226B0C5357a377E53B6DB12bDF5e64d",
  smartGangster: "0x2a1A101C9213fCf6844685d5886ea4107229b3db",
};

async function main() {
  await hardhat.run("compile");

  const Strategy = await ethers.getContractFactory("StrategyHoesVaultV2");
  const strategy = await Strategy.deploy(config.smartGangster, config.vault);
  await strategy.deployed();

  console.log("Candidate deployed to:", strategy.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
