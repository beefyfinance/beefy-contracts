import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { predictAddresses } from "../../utils/predictAddresses";
import { setCorrectCallFee } from "../../utils/setCorrectCallFee";
import { verifyContract } from "../../utils/verifyContract";
import { BeefyChain } from "../../utils/beefyChain";

const registerSubsidy = require("../../utils/registerSubsidy");

const {
  platforms: { stargate, beefyfinance },
  tokens: {
    USDC: { address: USDC },
    STG: { address: STG },
    ETH: { address: ETH },
  },
} = addressBook.arbitrum;

const shouldVerifyOnEtherscan = false;

const rewardPool = web3.utils.toChecksumAddress("0x6694340fc020c5E6B96567843da2df01b2CE1eb6");
const lp = web3.utils.toChecksumAddress("0x892785f33CdeE22A30AEF750F285E18c18040c3e");

const vaultParams = {
  mooName: "Moo StgArbUSDC",
  mooSymbol: "MooStgArbUSDC",
  delay: 21600,
};

const strategyParams = {
  want: lp,
  rewardPool: rewardPool,
  unirouter: "0x53Bf833A5d6c4ddA888F69c22C88C9f356a41614",
  strategist: "0x16eB1deaE4C4c32805da237dB93771b4cb12416A",
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToNativeRoute: [STG, ETH],
  outputToLp0Route: [USDC],
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyStargateOp",
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
    strategyParams.rewardPool,
    vault.address,
    strategyParams.unirouter,
    strategyParams.keeper,
    strategyParams.strategist,
    strategyParams.beefyFeeRecipient,
    strategyParams.outputToNativeRoute,
   // strategyParams.outputToLp0Route,
   // strategyParams.outputToLp1Route,
  ];
  const strategy = await Strategy.deploy(...strategyConstructorArguments);
  await strategy.deployed();

  // add this info to PR
  console.log();
  console.log("Vault:", vault.address);
  console.log("Strategy:", strategy.address);
  console.log("Want:", strategyParams.want);
  console.log("RewardPool:", strategyParams.rewardPool);

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
  await setCorrectCallFee(strategy, hardhat.network.name as BeefyChain);
  console.log(`Transfering Vault Owner to ${beefyfinance.vaultOwner}`)
  await vault.transferOwnership(beefyfinance.vaultOwner);
  console.log();

  await Promise.all(verifyContractsPromises);

  if (hardhat.network.name === "arbitrum") {
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
  