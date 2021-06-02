const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");

const { addressBook } = require("blockchain-addressbook")
const { USDC: { address: USDC }, USDT: { address: USDT }, QUICK: { address: QUICK }, WMATIC: { address: WMATIC }, ETH: { address: ETH } } = addressBook.polygon.tokens;
const { quickswap, beefyfinance } = addressBook.polygon.platforms;

const ethers = hardhat.ethers;

const vaultParams = {
  mooName: "Moo Quick USDC-USDT",
  mooSymbol: "mooquickUSDC-USDT",
  delay: 21600,
}

const strategyParams = {
  want: "0x2cf7252e74036d1da831d11089d326296e64a728",
  rewardPool: "0x251d9837a13F38F3Fe629ce2304fa00710176222",
  unirouter: quickswap.router,
  strategist: "0x4e3227c0b032161Dd6D780E191A590D917998Dc7", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToNativeRoute: [ QUICK, WMATIC ],
  outputToLp0Route: [ QUICK, ETH, USDC ],
  outputToLp1Route: [ QUICK, ETH, USDT ]
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyCommonRewardPoolLP"
}

async function main() {
  if (Object.values(vaultParams).some((v) => v === undefined) || Object.values(strategyParams).some((v) => v === undefined) || Object.values(contractNames).some((v) => v === undefined)) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory(contractNames.vault);
  const Strategy = await ethers.getContractFactory(contractNames.strategy);

  const [deployer] = await ethers.getSigners();
  const rpc = getNetworkRpc(hardhat.network.name);

  console.log("Deploying:", vaultParams.mooName);

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc });

  const vault = await Vault.deploy(predictedAddresses.strategy, vaultParams.mooName, vaultParams.mooSymbol, vaultParams.delay);
  await vault.deployed();

  const strategy = await Strategy.deploy(
    strategyParams.want,
    strategyParams.rewardPool,
    vault.address,
    strategyParams.unirouter,
    strategyParams.keeper,
    strategyParams.strategist,
    strategyParams.beefyFeeRecipient,
    strategyParams.outputToNativeRoute,
    strategyParams.outputToLp0Route,
    strategyParams.outputToLp1Route
  );
  await strategy.deployed();

  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);

  if (hardhat.network.name === "bsc") {
    await registerSubsidy(vault.address, deployer);
    await registerSubsidy(strategy.address, deployer);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
