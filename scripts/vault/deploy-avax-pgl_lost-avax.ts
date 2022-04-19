import hardhat, { ethers, web3 } from "hardhat";
import { predictAddresses } from "../../utils/predictAddresses";
import { setCorrectCallFee } from "../../utils/setCorrectCallFee";
import { setPendingRewardsFunctionName } from "../../utils/setPendingRewardsFunctionName";
import { verifyContract } from "../../utils/verifyContract";
import { BeefyChain } from "../../utils/beefyChain";
// import { checkGas } from "../../utils/checkGas";

import { avax } from "blockchain-addressbook/build/address-book/avax";
import { BigNumber } from "ethers";

const registerSubsidy = require("../../utils/registerSubsidy");


const {
  platforms: { pangolin, beefyfinance },
  tokens: {
    WAVAX: { address: WAVAX },
    PNG: { address: PNG },
    LOST: { address: LOST },
  },
} = avax;

const shouldCheckGas = true; // You can use this on a live deployment to delay until gas is cheap
const shouldVerifyOnEtherscan = true; // Always verify on live deployment
const shouldTransferOwner = false; // Always
const shouldSetPendingRewardsFunctionName = false; // Used for some strats and not others
const shouldHarvestOnDeposit = false; // Used for low fee chains (callFee = 11)

const gasLimit = BigNumber.from(web3.utils.toWei("40", "Gwei"));

const vaultParams = {
  mooName: "Moo Pangolin LOST-AVAX",
  mooSymbol: "mooPangolinLOST-AVAX",
  delay: 21600,
};

const vaultOwner = beefyfinance.vaultOwner;
const strategyOwner = beefyfinance.strategyOwner;

const strategyParams = {
  want: "0x8461681211B49c15e20B3Cfd4c63BE258878B7D9",
  chef: pangolin.minichef,
  poolId: 	105,
  unirouter: pangolin.router,
  strategist: "0x5577d38C6Ae74C73b33061e4886a262f88cdF45d", // insert your wallet here
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToNativeRoute: [PNG, WAVAX],
  outputToLp0Route: [PNG, WAVAX, LOST],
  outputToLp1Route: [PNG, WAVAX],
  pendingRewardsFunctionName: "pendingSpirit", // unused for GaugeLP
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyPangolinMiniChefLP",
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
  
  if (!checksumAddresses()) {
    console.error("one of address checksums is invalid");
    return;
  }

  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory(contractNames.vault);
  const Strategy = await ethers.getContractFactory(contractNames.strategy);

  const [deployer] = await ethers.getSigners();

  if (shouldCheckGas) {
    await checkGasLimits();
  }

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

  // add this info to PR
  console.log();
  console.log("Vault:", vault.address);
  console.log("Strategy:", strategy.address);
  console.log("Want:", strategyParams.want);
  console.log("Pool ID:", strategyParams.poolId);

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
  if (shouldSetPendingRewardsFunctionName) {
    await setPendingRewardsFunctionName(strategy, strategyParams.pendingRewardsFunctionName);
  }
  await setCorrectCallFee(strategy, hardhat.network.name as BeefyChain);
  if (shouldHarvestOnDeposit) {
    await strategy.setHarvestOnDeposit(true);
  }
  if (shouldTransferOwner) {
    console.log(`Transfering Vault Owner to ${beefyfinance.vaultOwner}`);
    await vault.transferOwnership(beefyfinance.vaultOwner);
  }

  console.log();

  await Promise.all(verifyContractsPromises);

  if (hardhat.network.name === "bsc") {
    await registerSubsidy(vault.address, deployer);
    await registerSubsidy(strategy.address, deployer);
  }
}

const checksumAddresses = () => {
  const result =
    web3.utils.checkAddressChecksum(strategyParams.want) && web3.utils.checkAddressChecksum(strategyParams.strategist);
  if (!result) {
    console.log(`want: ${web3.utils.checkAddressChecksum(strategyParams.want)}
      strategist: ${web3.utils.checkAddressChecksum(strategyParams.strategist)}`);
  }
  return result;
};

const checkGas = async () => {
  const gasPrice = await ethers.provider.getGasPrice();
  const gasPriceGwei = ethers.utils.formatUnits(gasPrice, "gwei");

  console.log(`Current gas: ${gasPriceGwei} gwei`);
  return gasPrice;
};

const checkGasLimits = async () => {
  console.log(`Checking gas price against limit ${gasLimit}`);
  let gasPrice = await checkGas();
  while (gasPrice >= gasLimit) {
    console.log(
      `Gas price ${ethers.utils.formatEther(gasPrice)} is higher than limit ${ethers.utils.formatEther(gasLimit)}`
    );
    await new Promise(resolve => setTimeout(resolve, 15 * 1000)); // sleep 60 seconds
    gasPrice = await checkGas();
  }
  return gasPrice;
};

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });