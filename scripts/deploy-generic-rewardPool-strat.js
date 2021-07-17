const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const { getNetworkRpc } = require("../utils/getNetworkRpc");

const { addressBook } = require("blockchain-addressbook")
const { DFYN: { address: DFYN }, ICE: { address: ICE }, ETH: { address: ETH } } = addressBook.polygon.tokens;
const { dfyn, beefyfinance } = addressBook.polygon.platforms;

const ethers = hardhat.ethers;

const vaultParams = {
  mooName: "Moo DFYN ICE-DFYN",
  mooSymbol: "mooDfynICE-DFYN",
  delay: 21600,
}

const strategyParams = {
  want: "0x9bb608dc0F9308B9beCA2F7c80865454d02E74cA",
  rewardPool: "0xD854E7339840F7D1E12B54FD75235eBc0bB6BfAC",
  unirouter: dfyn.router,
  strategist: "0x010dA5FF62B6e45f89FA7B2d8CEd5a8b5754eC1b", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToIntermediateRoute: [ DFYN, ETH ],
  outputToLp0Route: [ DFYN, ICE ],
  outputToLp1Route: [ DFYN ]
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyDFYNRewardPoolLP"
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

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc });

  const vault = await Vault.deploy(predictedAddresses.strategy, vaultParams.mooName, vaultParams.mooSymbol, vaultParams.delay);
  await vault.deployed();

  const strategy = await Strategy.deploy(
    strategyParams.want,
    strategyParams.rewardPool,
    vault.address,
    strategyParams.unirouter,
    strategyParams.keeper,
    strategyParams.strategist,
    strategyParams.beefyFeeRecipient,
    strategyParams.outputToIntermediateRoute,
    strategyParams.outputToLp0Route,
    strategyParams.outputToLp1Route
  );
  await strategy.deployed();

  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);

  if (hardhat.network.name === "bsc") {
    await registerSubsidy(vault.address, deployer);
    await registerSubsidy(strategy.address, deployer);
  }
/* 
  await hardhat.run("verify:verify", {
    address: vault.address,
    constructorArguments: [
      strategy.address, vaultParams.mooName, vaultParams.mooSymbol, vaultParams.delay
    ],
  })
 
  await hardhat.run("verify:verify", {
    address: "0x6ef302f46543d1045F3c93D2eE77AcD58d3854C4",
    constructorArguments: [
      strategyParams.want,
      strategyParams.rewardPool,
      "0xB198A916123394f2d9c31D4645468566e87080d5",
      strategyParams.unirouter,
      strategyParams.keeper,
      strategyParams.strategist,
      strategyParams.beefyFeeRecipient,
      strategyParams.outputToIntermediateRoute,
      strategyParams.outputToLp0Route,
      strategyParams.outputToLp1Route
    ],
   
  })
 */
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
