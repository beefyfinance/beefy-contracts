const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");

const ethers = hardhat.ethers;

const config = {
  want: "0x7cd05f8b960Ba071FdF69C750c0E5a57C8366500",
  poolId: 34,
  strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
  vault: "0xB194bcA26660abC93042fd6b475F2dD0b5175ED7",
};

async function main() {
  await hardhat.run("compile");

  const [deployer] = await ethers.getSigners();

  const Strategy = await ethers.getContractFactory("StrategyCakeCommunityLP");
  const strategy = await Strategy.deploy(config.want, config.poolId, config.vault, config.strategist);
  await strategy.deployed();

  console.log("Candidate deployed to:", strategy.address);

  await registerSubsidy(strategy.address, deployer);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
