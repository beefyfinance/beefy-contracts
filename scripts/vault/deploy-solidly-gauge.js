import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { predictAddresses } from "../../utils/predictAddresses";


const registerSubsidy = require("../../utils/registerSubsidy");

const {
  platforms: {  velodrome, beefyfinance },
  tokens: {
    SNX: { address: SNX },
    sUSD: { address: sUSD },
    ETH: { address: ETH },
    VELO: { address: VELO },
    USDC: { address: USDC },
  },
} = addressBook.optimism;


const want = web3.utils.toChecksumAddress("0x85FF5b70de43FeE34F3fA632adDD9F76a0f6bAA9");
const gauge = web3.utils.toChecksumAddress("0xFC4B6deA9276D906AD36828dc2e7DbaCfC01B47f");
//const ensId = ethers.utils.formatBytes32String("cake.eth");

const vaultParams = {
  mooName: "Moo Velodrome SNX-sUSD",
  mooSymbol: "mooVelodromeSNX-sUSD",
  delay: 21600,
};

const strategyParams = {
  want: want,
  gauge: gauge,
  unirouter: velodrome.router,
  strategist: "0xb2e4A61D99cA58fB8aaC58Bb2F8A59d63f552fC0", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  feeConfig: beefyfinance.beefyFeeConfig,
  outputToNativeRoute: [[VELO, ETH]],
  outputToLp0Route: [[VELO, USDC, false],[USDC, sUSD, true],[sUSD, SNX, false]],
  outputToLp1Route: [[VELO, USDC, false],[USDC, sUSD, true]],
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


 // await setPendingRewardsFunctionName(strategy, strategyParams.pendingRewardsFunctionName);
  await vault.transferOwnership(beefyfinance.vaultOwner);
  console.log(`Transfered Vault Ownership to ${beefyfinance.vaultOwner}`);

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