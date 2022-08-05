import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { predictAddresses } from "../../utils/predictAddresses";

const {
  platforms: { velodrome, beefyfinance },
  tokens: {
    WBTC: { address: WBTC },
    OP: {address: OP},
    ETH: { address: ETH },
    USDC: { address: USDC },
    DAI: { address: DAI },
  },
} = addressBook.optimism;

const vaultParams = {
  mooName: "Moo Aave Op USDC",
  mooSymbol: "mooAaveOpUSDC",
  delay: 21600,
};

const strategyParams = {
  dataProvider: "0x69FA688f1Dc47d4B5d8029D5a35FB7a548310654",
  lendingPool: "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
  incentivesController:"0x929EC64c34a17401F460460D4B9390518E5B473e",
  nativeToWantRoute: [[ETH, USDC, false]],
  outputToNativeRoute: [OP, ETH, false],
  unirouter: velodrome.router,
  keeper: beefyfinance.keeper,
  strategist: process.env.STRATEGIST_ADDRESS,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  feeconfig: beefyfinance.beefyFeeConfig,
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyAaveSupplyOnlyOptimism",
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

  const commonAddresses = [
    vault.address,
    strategyParams.unirouter,
    strategyParams.keeper,
    strategyParams.strategist,
    strategyParams.beefyFeeRecipient,
    strategyParams.feeconfig
  ];

  const strategyConstructorArguments = [
    strategyParams.dataProvider,
    strategyParams.lendingPool,
    strategyParams.incentivesController,
    commonAddresses,
    strategyParams.nativeToWantRoute,
    strategyParams.outputToNativeRoute
  ];
  const strategy = await Strategy.deploy(...strategyConstructorArguments);
  await strategy.deployed();

  // add this info to PR
  console.log();
  console.log("Vault:", vault.address);
  console.log("Strategy:", strategy.address);

  console.log();
  console.log("Running post deployment");

  console.log();

  console.log(`Transfering Vault Owner to ${beefyfinance.vaultOwner}`)
  await vault.transferOwnership(beefyfinance.vaultOwner);
  console.log();
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
