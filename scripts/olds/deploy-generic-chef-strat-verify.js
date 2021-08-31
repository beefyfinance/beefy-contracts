const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");
const { addressBook } = require("blockchain-addressbook")
const { LHB: {address: LHB}, WHT: {address: WHT}, USDT: {address: USDT}  } = addressBook.heco.tokens;
const { beefyfinance } = addressBook.heco.platforms;

const ethers = hardhat.ethers;

const vaultParams = {
  mooName: "Moo Lendhub LHB-USDT",
  mooSymbol: "mooLendhubLHB-USDT",
  delay: 21600,
}

const strategyParams = {
  want: "0x023f375a51Af8645D7446ba5942BAeDc53B0582D",
  poolId: 1,
  chef: "0x00A5BF6ab1166bce027D9d4b0E829f92781ab1A7",
  unirouter: "0xED7d5F38C79115ca12fe6C0041abb22F0A06C300",
  strategist: "0x010dA5FF62B6e45f89FA7B2d8CEd5a8b5754eC1b", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToNativeRoute: [ LHB, WHT ],
  outputToLp0Route: [  ],
  outputToLp1Route: [ LHB, USDT ]
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyCommonChefLP"
}

async function main() {
  if (Object.values(vaultParams).some((v) => v === undefined) || Object.values(strategyParams).some((v) => v === undefined) || Object.values(contractNames).some((v) => v === undefined)) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory(contractNames.vault);
  const Strategy = await ethers.getContractFactory(contractNames.strategy);

  const [deployer] = await ethers.getSigners();
  const rpc = getNetworkRpc(hardhat.network.name);

  console.log("Deploying:", vaultParams.mooName);

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc: "https://http-mainnet.hecochain.com" });

  const vault = await Vault.deploy(predictedAddresses.strategy, vaultParams.mooName, vaultParams.mooSymbol, vaultParams.delay);
  await vault.deployed();

  const strategy = await Strategy.deploy(
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
    strategyParams.outputToLp1Route
  );
  await strategy.deployed();
  
  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);

  await hardhat.run("verify:verify", {
    address: vault.address,
    constructorArguments: [
      strategy.address, vaultParams.mooName, vaultParams.mooSymbol, vaultParams.delay
    ],
  })

  await hardhat.run("verify:verify", {
    address: strategy.address,
    constructorArguments: [
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
    strategyParams.outputToLp1Route
    ],
  })

  if (hardhat.network.name === "bsc") {
    await registerSubsidy(vault.address, deployer);
    await registerSubsidy(strategy.address, deployer);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
