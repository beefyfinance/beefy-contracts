import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { predictAddresses } from "../../utils/predictAddresses";

const registerSubsidy = require("../../utils/registerSubsidy");

const {
  platforms: { beethovenX, beefyfinance },
  tokens: {
    BAL: { address: BAL },
    ETH: { address: ETH },
    rETH: { address: rETH },
  },
} = addressBook.optimism;

const gauge = web3.utils.toChecksumAddress("0x38f79beFfC211c6c439b0A3d10A0A673EE63AFb4");

const vaultParams = {
  mooName: "Moo Beets Rocket Fuel ",
  mooSymbol: "mooBeetsRocketFuel",
  delay: 21600,
};

const strategyParams = {
  gauge: gauge,
  input: ETH,
  unirouter: beethovenX.router,
  strategist: process.env.STRATEGIST_ADDRESS,
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  beefyFeeConfig: beefyfinance.beefyFeeConfig,
  routes: [
    "0x4fd63966879300cafafbb35d157dc5229278ed2300020000000000000000002b", 
    "0x39965C9DAB5448482CF7E002F583C812CEB53046000100000000000000000003",
    "0x39965C9DAB5448482CF7E002F583C812CEB53046000100000000000000000003",
    "0xD6E5824B54F64CE6F1161210BC17EEBFFC77E031000100000000000000000006"

],
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyBeetsMultiRewardGauge",
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
    strategyParams.routes,
    strategyParams.gauge,
    strategyParams.input,
    [vault.address,
    strategyParams.unirouter,
    strategyParams.keeper,
    strategyParams.strategist,
    strategyParams.beefyFeeRecipient,
    strategyParams.beefyFeeConfig],
  ];
  const strategy = await Strategy.deploy(...strategyConstructorArguments);
  await strategy.deployed();

  // add this info to PR
  console.log();
  console.log("Vault:", vault.address);
  console.log("Strategy:", strategy.address);

  console.log();
  console.log("Running post deployment");

  console.log(`Transfering Vault Owner to ${beefyfinance.vaultOwner}`)
  await vault.transferOwnership(beefyfinance.vaultOwner);
  console.log();

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