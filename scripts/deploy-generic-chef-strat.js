const hardhat = require("hardhat");

import { getNetworkRpc } from "../utils/getNetworkRpc";
import { addressBook } from "blockchain-addressbook";
const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const { WBNB: { address: WBNB }, CAKE: { address: CAKE }, NFT: { address: NFT} } = addressBook.bsc.tokens;
const { pancake, beefyfinance } = addressBook.bsc.platforms;

const ethers = hardhat.ethers;

const want = web3.utils.toChecksumAddress("0x0ecc84c9629317a494f12Bc56aA2522475bF32e8");

const vaultParams = {
  mooName: "Moo CakeV2 NFT-BNB",
  mooSymbol: "mooCakeV2NFT-BNB",
  delay: 21600,
}

const strategyParams = {
  want: want,
  poolId: 457,
  chef: pancake.masterchef,
  unirouter: pancake.router,
  strategist: "0x010dA5FF62B6e45f89FA7B2d8CEd5a8b5754eC1b", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToNativeRoute: [ CAKE, WBNB ],
  outputToLp0Route: [ CAKE, WBNB, NFT ],
  outputToLp1Route: [ CAKE, WBNB ],
  pendingRewardsFunctionName: "pendingCake" // used for rewardsAvailable(), use correct function name from masterchef
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyCommonChefLPBsc"
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
  await strategy.setPendingRewardsFunctionName(strategyParams.pendingRewardsFunctionName);

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