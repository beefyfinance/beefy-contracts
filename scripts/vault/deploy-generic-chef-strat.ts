import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { predictAddresses } from "../../utils/predictAddresses";
import { setCorrectCallFee } from "../../utils/setCorrectCallFee";
import { setPendingRewardsFunctionName } from "../../utils/setPendingRewardsFunctionName";
import { verifyContract } from "../../utils/verifyContract";

const {
  platforms: { sushi, beefyfinance },
  tokens: {
    WMOVR_SUSHI: { address: MOVR },
    ETH: { address: ETH },
    USDT: { address: USDT },
    SUSHI: { address: SUSHI },
  },
} = addressBook.moonriver;

const shouldVerifyOnEtherscan = true;

const want = web3.utils.toChecksumAddress("0xB0A594e76A876DE40a7fda9819E5c4Ec6d9Fd222");

const vaultParams = {
  mooName: "Moo Sushi ETH-USDT",
  mooSymbol: "mooSushiETH-USDT",
  delay: 21600,
};

const strategyParams = {
  want,
  poolId: 2,
  chef: sushi.minichef,
  unirouter: "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506",
  strategist: "0xa776f91e4d67C8B3d2515D0E6F37eE6b73e24Cb0", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToNativeRoute: [SUSHI, ETH, MOVR],
  outputToLp0Route: [MOVR, ETH],
  outputToLp1Route: [MOVR, ETH, USDT],
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyMrSushiLP",
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
  console.log("PoolId:", strategyParams.poolId);

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
  await setCorrectCallFee(strategy, hardhat.network.name);
  console.log();

  await Promise.all(verifyContractsPromises);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
