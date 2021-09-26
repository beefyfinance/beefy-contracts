import hardhat, { web3 } from "hardhat";

import { getNetworkRpc } from "../utils/getNetworkRpc";
import { addressBook } from "blockchain-addressbook";
import { setCorrectCallFee } from "../utils/setCorrectCallFee";
const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const { WONE: { address: WONE }, SUSHI: { address: SUSHI }, USDC: { address: USDC}, USDT: {address: USDT } } = addressBook.one.tokens;
const { sushi, beefyfinance } = addressBook.one.platforms;

const ethers = hardhat.ethers;

const want = web3.utils.toChecksumAddress("0x2c7862b408bb3DBFF277110FFdE1B4EAa45C692a");

const vaultParams = {
  mooName: "Moo Sushi USDT-ONE",
  mooSymbol: "mooSushiUSDT-ONE",
  delay: 21600,
}

const strategyParams = {
  want: want,
  poolId: 2,
  chef: sushi.minichef,
  unirouter: sushi.router,
  strategist: "0x010dA5FF62B6e45f89FA7B2d8CEd5a8b5754eC1b", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: "0xaDB9DDFA24E326dC9d337561f6c7ba2a6Ecec697",
  outputToNativeRoute: [ SUSHI, WONE ],
  outputToLp0Route: [ SUSHI, WONE, USDT ],
  outputToLp1Route: [ SUSHI, WONE],
  pendingRewardsFunctionName: "pendingWise" // used for rewardsAvailable(), use correct function name from masterchef
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyMiniChefLP"
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
  const chainName = hardhat.network.name
  const rpc = getNetworkRpc(chainName);

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

  // post deploy
  await strategy.setPendingRewardsFunctionName(strategyParams.pendingRewardsFunctionName);
  await setCorrectCallFee(chainName, strategy);

  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);
  console.log("Want:", strategyParams.want);

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