const hardhat = require("hardhat");

// const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");

const { addressBook } = require("blockchain-addressbook")
const { USDC: { address: USDC }, USDT: { address: USDT }, QUICK: { address: QUICK }, WMATIC: { address: WMATIC }, ETH: { address: ETH }, DFYN: { address: DFYN }, UST: { address: UST } } = addressBook.polygon.tokens;
const { dfyn, beefyfinance } = addressBook.polygon.platforms;

const ethers = hardhat.ethers;

const vaultParams = {
  mooName: "Moo DFYN UST-USDT",
  mooSymbol: "mooDFYNUST-USDT",
  delay: 21600,
}

const strategyParams = {
  want: "0x39BEd7f1C412ab64443196A6fEcb2ac20C707224",
  rewardPool: "0x4B47d7299Ac443827d4468265A725750475dE9E6",
  unirouter: dfyn.router,
  strategist: "0x2C6bd2d42AaA713642ee7c6e83291Ca9F94832C6", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeConverterETHtoWMATIC,
  outputToNativeRoute: [ DFYN, ETH ],
  outputToLp0Route: [ DFYN, USDC, USDT, UST ],
  outputToLp1Route: [ DFYN, USDC, USDT ]
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyDFYNRewardPoolLP"
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
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
