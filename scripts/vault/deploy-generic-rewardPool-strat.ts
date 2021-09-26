import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { predictAddresses } from "../../utils/predictAddresses";
import { setCorrectCallFee } from "../../utils/setCorrectCallFee";
import { verifyContracts } from "../../utils/verifyContracts";

const registerSubsidy = require("../../utils/registerSubsidy");

const {
  WMATIC_DFYN: { address: WMATIC_DFYN },
  DFYN: { address: DFYN },
  CRV: { address: CRV },
  WMATIC: { address: WMATIC },
} = addressBook.polygon.tokens;
const { dfyn, beefyfinance } = addressBook.polygon.platforms;

const shouldVerifyOnEtherscan = false;

const want = web3.utils.toChecksumAddress("0x4ea3e2cfc39fa51df85ebcfa366d7f0eed448a1c");
const rewardPool = web3.utils.toChecksumAddress("0x098fdadCcde328e6CD1168125e1e7685eEa54342");

const vaultParams = {
  mooName: "Moo DFyn CRV-DFYN",
  mooSymbol: "mooDFynCRV-DFYN",
  delay: 21600,
};

const strategyParams = {
  want: want,
  rewardPool: rewardPool,
  unirouter: dfyn.router,
  strategist: "0x010dA5FF62B6e45f89FA7B2d8CEd5a8b5754eC1b", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToNativeRoute: [DFYN, WMATIC_DFYN],
  outputToLp0Route: [DFYN, CRV],
  outputToLp1Route: [DFYN],
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyDFYNRewardPoolLP",
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
  console.log("RewardPool:", strategyParams.rewardPool);

  console.log();
  console.log("Running post deployment");

  if (shouldVerifyOnEtherscan) {
    await verifyContracts(vault, vaultConstructorArguments, strategy, strategyConstructorArguments);
  }
  await setCorrectCallFee(strategy, hardhat.network.name);
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
