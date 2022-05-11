import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { predictAddresses } from "../../utils/predictAddresses";
import { setCorrectCallFee } from "../../utils/setCorrectCallFee";
import { setPendingRewardsFunctionName } from "../../utils/setPendingRewardsFunctionName";
import { verifyContract } from "../../utils/verifyContract";
import { BeefyChain } from "../../utils/beefyChain";

const registerSubsidy = require("../../utils/registerSubsidy");

const {
  platforms: {  stellaswap, beefyfinance },
  tokens: {
    GLMR: { address: GLMR },
    xcDOT: { address: xcDOT },
    STELLA: { address: STELLA },
    xSTELLA: { address: xSTELLA }
  },
} = addressBook.moonbeam;

const shouldVerifyOnEtherscan = false;

const want = web3.utils.toChecksumAddress("0x0eD7e52944161450477ee417DE9Cd3a859b14fD0");
const ensId = ethers.utils.formatBytes32String("cake.eth");

const vaultParams = {
  mooName: "Moo Stella",
  mooSymbol: "mooStella",
  delay: 21600,
};

const strategyParams = {
  want,
  poolId: 2,
  chef: "0xa5f8C5Dbd5F286960b9d90548680aE5ebFf07652", //pancake.masterchef,
  unirouter: pancake.router,
  strategist: "0x4cC72219fc8aEF162FC0c255D9B9C3Ff93B10882", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToNativeRoute: [CAKE, BNB],
  outputToLp0Route: [CAKE],
  outputToLp1Route: [CAKE, BNB],
  ensId
 // pendingRewardsFunctionName: "pendingTri", // used for rewardsAvailable(), use correct function name from masterchef
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyCommonChefLPVoter",
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

  console.log("Deploying:", vaultParams.mooName);

  const predictedAddresses = await predictAddresses({ creator: deployer.address });

  const vaultConstructorArguments = [
    predictedAddresses.strategy,
    vaultParams.mooName,
    vaultParams.mooSymbol,
    vaultParams.delay,
  ];
  const vault = await Vault.deploy(...vaultConstructorArguments);
  await vault.deployed();

  console.log();
  console.log("Vault:", vault.address);

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
    strategyParams.ensId
  ];
  const strategy = await Strategy.deploy(...strategyConstructorArguments);
  await strategy.deployed();

  // add this info to PR
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
 // await setPendingRewardsFunctionName(strategy, strategyParams.pendingRewardsFunctionName);
  await setCorrectCallFee(strategy, hardhat.network.name as BeefyChain);
  console.log(`Transfering Vault Owner to ${beefyfinance.vaultOwner}`)
  await vault.transferOwnership(beefyfinance.vaultOwner);
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