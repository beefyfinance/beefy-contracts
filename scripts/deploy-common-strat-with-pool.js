const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");

const { addressBook } = require("blockchain-addressbook")
const { QUICK: { address: QUICK }, WMATIC: { address: WMATIC }, ETH: { address: ETH } } = addressBook.polygon.tokens;
const { quickswap, beefyfinance } = addressBook.polygon.platforms;

const ethers = hardhat.ethers;

const config = {
  want: "0x2cf7252e74036d1da831d11089d326296e64a728",
  mooName: "Moo Quick USDC-USDT",
  mooSymbol: "mooquickUSDC-USDT",
  delay: 21600,
  strategyName: "StrategyRewardPoolCommon",
  rewardPool: "0x251d9837a13F38F3Fe629ce2304fa00710176222",
  unirouter: quickswap.router,
  strategist: "0x4e3227c0b032161Dd6D780E191A590D917998Dc7", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToNativeRoute: [ QUICK, WMATIC ],
  outputToPairedWithLp0Route: [ QUICK, ETH ],
  outputToPairedWithLp1Route: [ QUICK, ETH ]
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
    config.outputToPairedWithLp0Route,
    config.outputToPairedWithLp1Route
  );
  await strategy.deployed();

  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
