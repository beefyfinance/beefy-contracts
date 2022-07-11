import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { predictAddresses } from "../../utils/predictAddresses";
import { setCorrectCallFee } from "../../utils/setCorrectCallFee";
import { verifyContract } from "../../utils/verifyContract";
import { BeefyChain } from "../../utils/beefyChain";

const registerSubsidy = require("../../utils/registerSubsidy");

const {
  platforms: {  velodrome, beefyfinance },
  tokens: {
    OP: { address: OP },
    ETH: { address: ETH },
    VELO: { address: VELO },
    USDC: { address: USDC },
  },
} = addressBook.optimism;

const shouldVerifyOnEtherscan = false;

const want = web3.utils.toChecksumAddress("0xcdd41009E74bD1AE4F7B2EeCF892e4bC718b9302");
const gauge = web3.utils.toChecksumAddress("0x2f733b00127449fcF8B5a195bC51Abb73B7F7A75");
//const ensId = ethers.utils.formatBytes32String("cake.eth");

const vaultParams = {
  mooName: "Moo Velodrome OP-ETH",
  mooSymbol: "mooVelodromeOP-ETH",
  delay: 21600,
};

const strategyParams = {
  want: want,
  gauge: gauge,
  unirouter: velodrome.router,
  strategist: "0xb2e4A61D99cA58fB8aaC58Bb2F8A59d63f552fC0", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToNativeRoute: [[VELO, ETH]],
  outputToLp0Route: [[VELO, ETH]],
  outputToLp1Route: [[VELO, ETH],[ETH, OP]],
  bools: [[false],[false],[false, false]],
  verifyStrat: false,
 // ensId
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyCommonSolidlyGaugeLP",
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

  const strategyConstructorArguments = [
    strategyParams.want,
    strategyParams.gauge,
    vault.address,
    strategyParams.unirouter,
    strategyParams.keeper,
    strategyParams.strategist,
    strategyParams.beefyFeeRecipient,
  ];

  const strategy = await Strategy.deploy(...strategyConstructorArguments);
  await strategy.deployed();

  // add this info to PR
  console.log();
  console.log("Vault:", vault.address);
  console.log("Strategy:", strategy.address);
  console.log("Want:", strategyParams.want);
  console.log("gauge:", strategyParams.gauge);

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
  await strategy.intializeRoutes(strategyParams.outputToNativeRoute, strategyParams.outputToLp0Route, strategyParams.outputToLp1Route, strategyParams.bools);
  console.log("Strategy Routes Intialized");



  await Promise.all(verifyContractsPromises);

  if (hardhat.network.name === "bsc") {
    await registerSubsidy(vault.address, deployer);
    await registerSubsidy(strategy.address, deployer);
  }

  if (strategyParams.verifyStrat) {
    console.log("verifying contract...")
    await hardhat.run("verify:verify", {
      address: strategy.address,
      constructorArguments: [
        ...strategyConstructorArguments
      ],
    })
  }
 

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });