import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { predictAddresses } from "../../utils/predictAddresses";
import { setCorrectCallFee } from "../../utils/setCorrectCallFee";
import { verifyContract } from "../../utils/verifyContract";
import { BeefyChain } from "../../utils/beefyChain";

const registerSubsidy = require("../../utils/registerSubsidy");

const {
  platforms: { quickswap, beefyfinance },
  tokens: {
    stMATIC: { address: stMATIC },
    MATIC: { address: MATIC },
    LDO: { address: LDO },
    CRV: { address: CRV }
  },
} = addressBook.polygon;

const shouldVerifyOnEtherscan = false;

const gauge = web3.utils.toChecksumAddress("0x9633E0749faa6eC6d992265368B88698d6a93Ac0");
const gaugeFactory = web3.utils.toChecksumAddress("0xabC000d88f23Bb45525E447528DBF656A9D55bf5");
const lp =  web3.utils.toChecksumAddress("0xe7CEA2F6d7b120174BF3A9Bc98efaF1fF72C997d");
const pool = web3.utils.toChecksumAddress("0xFb6FE7802bA9290ef8b00CA16Af4Bc26eb663a28");

const vaultParams = {
  mooName: "Moo Curve stMATIC-MATIC",
  mooSymbol: "mooCurvestMATIC-MATIC",
  delay: 21600,
};

const strategyParams = {
  want: lp,
  gauge: gauge,
  gaugeFactory: gaugeFactory,
  pool: pool,
  poolSize: 2, 
  depositIndex: 0,
  useUnderlying: false,
  useMeta: false,
  unirouter: quickswap.router,
  strategist: "0xb2e4A61D99cA58fB8aaC58Bb2F8A59d63f552fC0", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  crvToNativeRoute: [CRV, MATIC],
  nativeToDepositRoute: [MATIC, stMATIC],
  crvEnabled: false, 
  addReward: true,
  rewardToNativeRoute: [LDO, MATIC],
  minAmount: 1000,
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyCurveLP",
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
    strategyParams.gaugeFactory,
    strategyParams.gauge,
    strategyParams.pool,
    strategyParams.poolSize,
    strategyParams.depositIndex,
    strategyParams.useUnderlying,
    strategyParams.useMeta,
    strategyParams.crvToNativeRoute,
    strategyParams.nativeToDepositRoute,
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
  console.log("Want:", strategyParams.want);
  console.log("Gauge:", strategyParams.gauge);

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
  console.log(`Transfering Vault Owner to ${beefyfinance.vaultOwner}`)
  await vault.transferOwnership(beefyfinance.vaultOwner);
  console.log(`setting needed functions`);
  if (!strategyParams.crvEnabled) {
    await strategy.setCrvEnabled(strategyParams.crvEnabled);
  }
  if (strategyParams.addReward) {
    await strategy.addRewardToken(strategyParams.rewardToNativeRoute, strategyParams.minAmount);
  }
  console.log();
  console.log('fin');

  await Promise.all(verifyContractsPromises);

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
  