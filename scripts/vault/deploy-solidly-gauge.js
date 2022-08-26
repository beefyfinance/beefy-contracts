import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { predictAddresses } from "../../utils/predictAddresses";


const registerSubsidy = require("../../utils/registerSubsidy");

const {
  platforms: {  spiritswap, beefyfinance },
  tokens: {
    SPIRIT: { address: SPIRIT},
    BIFI: { address: BIFI },
    FTM: { address: FTM },
    USDC: { address: USDC },
    FRAX: { address: FRAX },
    DAI: { address: DAI },
    fUSDT: { address: fUSDT },
  },
} = addressBook.fantom;


const want = web3.utils.toChecksumAddress("0x912B333dDaFC925f63C9746E5115A2CD5290b59e");
const gauge = web3.utils.toChecksumAddress("0x87Cae38ECb34FF4D3239A789F7709f285484F7e1");
const binSpiritGauge = web3.utils.toChecksumAddress("0x44e314190D9E4cE6d4C0903459204F8E21ff940A");
//const ensId = ethers.utils.formatBytes32String("cake.eth");

const vaultParams = {
  mooName: "Moo SpiritV2 SPIRIT-FTM",
  mooSymbol: "mooSpiritV2SPIRIT-FTM",
  delay: 21600,
};

const strategyParams = {
  want: want,
  gauge: gauge,
  unirouter: spiritswap.router,
  gaugeStaker: binSpiritGauge,
  strategist: "0xb2e4A61D99cA58fB8aaC58Bb2F8A59d63f552fC0", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  feeConfig: beefyfinance.beefyFeeConfig,
  outputToNativeRoute: [[SPIRIT, FTM, false]],
  outputToLp0Route: [[SPIRIT, FTM, false]],
  outputToLp1Route: [[SPIRIT, SPIRIT, false]],
  verifyStrat: false,
  spiritswapStrat: true,
  gaugeStakerStrat: true
 // ensId
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: strategyParams.gaugeStakerStrat ? "StrategyCommonSolidlyStakerLP" : "StrategyCommonSolidlyGaugeLP",
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

  const strategyConstructorArgumentsStaker = [
    strategyParams.want,
    strategyParams.gauge,
    strategyParams.gaugeStaker,
    [
      vault.address,
      strategyParams.unirouter,
      strategyParams.keeper,
      strategyParams.strategist,
      strategyParams.beefyFeeRecipient,
      strategyParams.feeConfig,
    ],
    strategyParams.outputToNativeRoute,
    strategyParams.outputToLp0Route, 
    strategyParams.outputToLp1Route
  ];

  const strategyConstructorArguments = [
    strategyParams.want,
    strategyParams.gauge,
    [
      vault.address,
      strategyParams.unirouter,
      strategyParams.keeper,
      strategyParams.strategist,
      strategyParams.beefyFeeRecipient,
      strategyParams.feeConfig,
    ],
    strategyParams.outputToNativeRoute,
    strategyParams.outputToLp0Route, 
    strategyParams.outputToLp1Route
  ];

  const strategy = strategyParams.gaugeStakerStrat 
    ? await Strategy.deploy(...strategyConstructorArgumentsStaker) 
    : await Strategy.deploy(...strategyConstructorArguments); 
  await strategy.deployed();

  // add this info to PR
  console.log();
  console.log("Vault:", vault.address);
  console.log("Strategy:", strategy.address);
  console.log("Want:", strategyParams.want);
  console.log("gauge:", strategyParams.gauge);

  console.log();
  console.log("Running post deployment");


 // await setPendingRewardsFunctionName(strategy, strategyParams.pendingRewardsFunctionName);
  await vault.transferOwnership(beefyfinance.vaultOwner);
  console.log(`Transfered Vault Ownership to ${beefyfinance.vaultOwner}`);

  if (strategyParams.spiritswapStrat) {
    console.log(`Setting Spirit Harvest to True`);
    await strategy.setSpiritHarvest(true);
  }

  if (hardhat.network.name === "bsc") {
    await registerSubsidy(vault.address, deployer);
    await registerSubsidy(strategy.address, deployer);
  }

  if (strategyParams.verifyStrat) {
    console.log("verifying contract...")

    if (strategyParams.gaugeStakerStrat) {
      await hardhat.run("verify:verify", {
        address: strategy.address,
        constructorArguments: [
          ...strategyConstructorArgumentsStaker
        ],
      })
    } else {
      await hardhat.run("verify:verify", {
        address: strategy.address,
        constructorArguments: [
          ...strategyConstructorArguments
        ],
      })
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });