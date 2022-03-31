import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { predictAddresses } from "../../utils/predictAddresses";
import { setCorrectCallFee } from "../../utils/setCorrectCallFee";
import { verifyContract } from "../../utils/verifyContract";
import { BeefyChain } from "../../utils/beefyChain";

const registerSubsidy = require("../../utils/registerSubsidy");

const {
  platforms: { pancake, beefyfinance },
  tokens: {
    BIFI: { address: BIFI },
    WBNB: { address: WBNB },
  },
} = addressBook.bsc;

const shouldVerifyOnEtherscan = true;

const rewardPool = web3.utils.toChecksumAddress("0x0d5761D9181C7745855FC985f646a842EB254eB9");
const lp = web3.utils.toChecksumAddress("0xCa3F508B8e4Dd382eE878A314789373D80A5190A");

const vaultParams = {
  mooName: "MooBIFIV2",
  mooSymbol: "mooBIFIV2",
  delay: 21600,
};

const strategyParams = {
  want: BIFI,
  rewardPool: rewardPool,
  unirouter: pancake.router,
  strategist: ethers.constants.AddressZero, // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: "0x7E3D8b6E70Bbe8796f7db3229e49564E0180CB37",
 // outputToNativeRoute: [FTM],
  outputToLp0Route: [WBNB, BIFI],
 // outputToLp1Route: [QUICK, MATIC, MAI],
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyBifiMaxiV4",
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
   // strategyParams.outputToNativeRoute,
    strategyParams.outputToLp0Route,
//   strategyParams.outputToLp1Route,
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
  