const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");
const { addressBook } = require("blockchain-addressbook")
const { EPS: { address: EPS }, WBNB: { address: WBNB }, BUSD: { address: BUSD } } = addressBook.bsc.tokens;
const { pancake, beefyfinance } = addressBook.bsc.platforms;

const ethers = hardhat.ethers;

const config = {
  want: EPS,
  mooName: "Moo Ellipsis EPS",
  mooSymbol: "mooEllipsisEPS",
  delay: 21600,
  strategyName: "StrategyMultiFeeDistribution",
  rewardPool: "0x4076CC26EFeE47825917D0feC3A79d0bB9a6bB5c",
  unirouter: pancake.router,
  strategist: "0x4e3227c0b032161Dd6D780E191A590D917998Dc7", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToNativeRoute: [ BUSD, WBNB ],
  outputToWantRoute: [ BUSD, WBNB, EPS ]
};

async function main() {
  if (Object.values(config).some((v) => v === undefined)) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory("BeefyVaultV6");
  const Strategy = await ethers.getContractFactory(config.strategyName);

  const [deployer] = await ethers.getSigners();
  const rpc = getNetworkRpc(hardhat.network.name);

  console.log("Deploying:", config.mooName);

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc });

  const vault = await Vault.deploy(predictedAddresses.strategy, config.mooName, config.mooSymbol, config.delay);
  await vault.deployed();

  const strategy = await Strategy.deploy(
    config.want,
    config.rewardPool,
    predictedAddresses.vault,
    config.unirouter,
    config.keeper,
    config.strategist,
    config.beefyFeeRecipient,
    config.outputToNativeRoute,
    config.outputToWantRoute
  );
  await strategy.deployed();

  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);

  await registerSubsidy(vault.address, deployer);
  await registerSubsidy(strategy.address, deployer);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
