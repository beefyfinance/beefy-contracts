const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses").predictAddresses;
const getNetworkRpc = require("../utils/getNetworkRpc");
const { addressBook } = require("blockchain-addressbook")
const { DAI: { address: DAI }, USDC: { address: USDC }, ETH: { address: ETH }, WMATIC: { address: WMATIC }, SUSHI: { address: SUSHI } } = addressBook.polygon.tokens;
const { sushi, beefyfinance } = addressBook.polygon.platforms;

const ethers = hardhat.ethers;

const vaultParams = {
  mooName: "Moo Sushi USDC-DAI",
  mooSymbol: "mooSushiUSDC-DAI",
  delay: 21600,
}

const strategyParams = {
  want: "0xcd578f016888b57f1b1e3f887f392f0159e26747",
  poolId: 11,
  chef: sushi.minichef,
  unirouter: sushi.router,
  strategist: "0x4e3227c0b032161Dd6D780E191A590D917998Dc7", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToNativeRoute: [ SUSHI, WMATIC ],
  outputToLp0Route: [ SUSHI, ETH, USDC ],
  outputToLp1Route: [ SUSHI, ETH, DAI ]
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyCommonChefLP"
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
    strategyParams.poolId,
    strategyParams.chef,
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
