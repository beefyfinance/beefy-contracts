const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");

const ethers = hardhat.ethers;

const config = {
  want: "0xC9849E6fdB743d08fAeE3E34dd2D1bc69EA11a51",
  output: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
  targetRewardPool: "0xCADc8CB26c8C7cB46500E61171b5F27e9bd7889D",
  vault: "0x9e16e999ab8e1f1f4ae04ae39aa3a75064db73a6",
  keeper: "0x9295E05d5cd1cfA617875Ba1cF984D65830d1a4c",
  strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
};

async function main() {
  await hardhat.run("compile");

  const [deployer] = await ethers.getSigners();

  const Strategy = await ethers.getContractFactory("StrategyRewardPoolBsc");
  const strategy = await Strategy.deploy(
    config.want,
    config.output,
    config.targetRewardPool,
    config.vault,
    config.keeper,
    config.strategist
  );
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
