import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { predictAddresses } from "../utils/predictAddresses";
import { setCorrectCallFee } from "../utils/setCorrectCallFee";
import { setPendingRewardsFunctionName } from "../utils/setPendingRewardsFunctionName";
import { verifyContract } from "../utils/verifyContract";
import { BeefyChain } from "../utils/beefyChain";

const registerSubsidy = require("../utils/registerSubsidy");

const {
  platforms: { pancake, beefyfinance },
  tokens: {
    BUSD: { address: BUSD },
    WBNB: { address: WBNB },
    CAKE: { address: CAKE },
  },
} = addressBook.bsc;

const IDIA = web3.utils.toChecksumAddress("0x0b15Ddf19D47E6a86A56148fb4aFFFc6929BcB89")
const want = web3.utils.toChecksumAddress("0x71E6de81381eFE0Aa98f56b3B43eB3727D640715") // Add the LP address.

const shouldVerifyOnEtherscan = false;

const vaultParams = {
  mooName: "Moo CakeV2 IDIA-BUSD", // Update the mooName.
  mooSymbol: "mooCakeV2IDIA-BUSD", // Update the mooSymbol.
  delay: 21600,
};

const strategyParams = {
  want,
  poolId: 484, // Add the LP id.
  chef: pancake.masterchef,
  unirouter: pancake.router,
  strategist: "0x2546bcd3c84621e976d8185a91a922ae77ecec30", // Add your public address.
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToNativeRoute: [CAKE, WBNB], // Add the route to convert from the reward token to the native token.
  outputToLp0Route: [CAKE, BUSD, IDIA], // Add the route to convert your reward token to token0.
  outputToLp1Route: [CAKE, BUSD], // Add the route to convert your reward token to token1.
  pendingRewardsFunctionName: "pendingCake", // used for rewardsAvailable(), use correct function name from masterchef
};

const contractNames = {
  vault: "BeefyVaultV6", // Add the vault name which will be deployed.
  strategy: "StrategyCommonChefLPBsc", // Add the strategy name which will be deployed along with the vault.
};

async function main() {
  if (
    Object.values(vaultParams).some(v => v === undefined) ||
    Object.values(strategyParams).some(v => v === undefined) ||
    Object.values(contractNames).some(v => v === undefined)
  ) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory(contractNames.vault);
  const Strategy = await ethers.getContractFactory(contractNames.strategy);

  const [deployer] = await ethers.getSigners();
  const predictedAddresses = await predictAddresses({ creator: deployer.address });
  
  console.log("Deploying:", vaultParams.mooName);
  const vaultConstructorArguments = [
    predictedAddresses.strategy,
    vaultParams.mooName,
    vaultParams.mooSymbol,
    vaultParams.delay,
  ];
  const vault = await Vault.deploy(...vaultConstructorArguments);
  await vault.deployed();
  console.log(vaultParams.mooName, "is now deployed");

  console.log("Deploying:", contractNames.strategy);
  const strategyConstructorArguments = [
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
    strategyParams.outputToLp1Route,
  ];
  const strategy = await Strategy.deploy(...strategyConstructorArguments);
  await strategy.deployed();
  console.log(contractNames.strategy, "is now deployed");


  // add this info to PR
  console.log();
  console.log("Vault:", vault.address);
  console.log("Strategy:", strategy.address);
  console.log("Want:", strategyParams.want);
  console.log("PoolId:", strategyParams.poolId);

  console.log();
  console.log("Running post deployment");

  const verifyContractsPromises: Promise<any>[] = [];
  if (shouldVerifyOnEtherscan) {
    // skip await as this is a long running operation, and you can do other stuff to prepare vault while this finishes
    verifyContractsPromises.push(
      verifyContract(vault.address, vaultConstructorArguments),
      verifyContract(strategy.address, strategyConstructorArguments)
    );
  }
  await setPendingRewardsFunctionName(strategy, strategyParams.pendingRewardsFunctionName);
  await setCorrectCallFee(strategy, hardhat.network.name as BeefyChain);
  console.log();

  await Promise.all(verifyContractsPromises);

  if (hardhat.network.name === "bsc") {
    await registerSubsidy(vault.address, deployer);
    await registerSubsidy(strategy.address, deployer);
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
