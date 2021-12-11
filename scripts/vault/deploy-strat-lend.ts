import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { predictAddresses } from "../../utils/predictAddresses";
import { setCorrectCallFee } from "../../utils/setCorrectCallFee";
import { verifyContract } from "../../utils/verifyContract";
import { BeefyChain } from "../../utils/beefyChain";

const {
  platforms: { spookyswap, beefyfinance },
  tokens: {
    SCREAM: { address: SCREAM },
    fUSDT: { address: fUSDT },
    WFTM: { address: WFTM },
    ETH: { address: ETH },
    WBTC: { address: WBTC },
    DAI: { address: DAI },
  },
} = addressBook.fantom;

const shouldVerifyOnEtherscan = false;

const iToken = web3.utils.toChecksumAddress("0x4565DC3Ef685E4775cdF920129111DdF43B9d882");

const vaultParams = {
  mooName: "Moo Scream WBTC",
  mooSymbol: "mooScreamWBTC",
  delay: 21600,
};

const strategyParams = {
  markets: [iToken],
  borrowRate: 72,
  borrowRateMax: 75,
  borrowDepth: 4,
  minLeverage: 1,
  outputToNativeRoute: [SCREAM, WFTM],
  outputToWantRoute: [SCREAM, WFTM, WBTC],
  unirouter: spookyswap.router,
  keeper: beefyfinance.keeper,
  strategist: "0x010dA5FF62B6e45f89FA7B2d8CEd5a8b5754eC1b",
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyScream",
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
    strategyParams.borrowRate,
    strategyParams.borrowRateMax,
    strategyParams.borrowDepth,
    strategyParams.minLeverage,
    strategyParams.outputToNativeRoute,
    strategyParams.outputToWantRoute,
    strategyParams.markets,
    vault.address,
    strategyParams.unirouter,
    strategyParams.keeper,
    strategyParams.strategist,
    strategyParams.beefyFeeRecipient,
  ];
  const strategy = await Strategy.deploy(...strategyConstructorArguments);
  await strategy.deployed();

  // add this info to PR
  console.log();
  console.log("Vault:", vault.address);
  console.log("Strategy:", strategy.address);
  console.log("Want:", strategyParams.outputToWantRoute[strategyParams.outputToWantRoute.length - 1]);

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
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
