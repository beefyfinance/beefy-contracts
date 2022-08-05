import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { predictAddresses } from "../../utils/predictAddresses";
import { setCorrectCallFee } from "../../utils/setCorrectCallFee";
import { verifyContract } from "../../utils/verifyContract";
import { BeefyChain } from "../../utils/beefyChain";

const {
  platforms: { spookyswap, spiritswap, beefyfinance },
  tokens: {
    TUSD: { address: TUSD },
    FTM: {address: FTM},
    USDC: { address: USDC },
    SCREAM: { address: SCREAM },
  },
} = addressBook.fantom;

const shouldVerifyOnEtherscan = false;

const vaultParams = {
  mooName: "Moo Scream Supply Test",
  mooSymbol: "mooScreamSupplyTest",
  delay: 0,
};

const strategyParams = {
//  want: Frax,
  borrowRate: 72,
  borrowRateMax: 75,
  borrowDepth: 4,
  minLeverage: 1000000000,
  outputToNativeRoute: [SCREAM, FTM],
  outputToWantRoute: [SCREAM, FTM, USDC, TUSD],
  markets: ["0x789B5DBd47d7Ca3799f8E9FdcE01bC5E356fcDF1"],
  unirouter: spookyswap.router,
  secondUnirouter: spiritswap.router,
  keeper: beefyfinance.keeper,
  strategist: "0xb2e4A61D99cA58fB8aaC58Bb2F8A59d63f552fC0",
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
};

const borrowConfig = [strategyParams.borrowRate, strategyParams.borrowRateMax, strategyParams.borrowDepth, strategyParams.minLeverage ]

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyScreamSupplyOnly",
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
    strategyParams.markets,
    strategyParams.outputToNativeRoute,
    strategyParams.outputToWantRoute,
   // strategyParams.secondUnirouter,
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

 // console.log(`Transfering Vault Owner to ${beefyfinance.vaultOwner}`)
 // await vault.transferOwnership(beefyfinance.vaultOwner);
 // console.log();

  await Promise.all(verifyContractsPromises);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });