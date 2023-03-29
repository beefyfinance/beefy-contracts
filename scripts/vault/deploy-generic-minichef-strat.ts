import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { setPendingRewardsFunctionName } from "../../utils/setPendingRewardsFunctionName";
import { verifyContract } from "../../utils/verifyContract";
import vaultV7 from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";

const {
  platforms: { beefyfinance, synapse, sushi },
  tokens: {
    SYN: { address: SYN },
    ETH: { address: ETH },
    SUSHI: { address: SUSHI },
  },
} = addressBook.ethereum;

const shouldVerifyOnEtherscan = false;

const want = web3.utils.toChecksumAddress("0x4a86c01d67965f8cb3d0aaa2c655705e64097c31");
let strategist: string;
if (!process.env.STRATEGIST_ADDRESS) {
  throw new Error("Set env var STRATEGIST_ADDRESS");
} else {
  strategist = web3.utils.toChecksumAddress(process.env.STRATEGIST_ADDRESS);
}

const vaultParams = {
  mooName: "Moo SynapseSushiLP ETH-SYN",
  mooSymbol: "mooSynapseSushiLPETH-SYN",
  delay: 21600,
};

const strategyParams = {
  strategyContractName: "StrategyCommonMiniChefLP",
  want: want,
  poolId: 0,
  chef: synapse.minichef,
  unirouter: sushi.router,
  strategist: strategist,
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  beefyFeeConfig: beefyfinance.beefyFeeConfig,
  beefyVaultProxy: "0xC551dDCE8e5E657503Cd67A39713c06F2c0d2e97", // beefyfinance.vaultProxy,
  outputToNativeRoute: [SYN, ETH],
  outputToLp0Route: [SYN],
  outputToLp1Route: [SYN, ETH],
  shouldSetPendingRewardsFunctionName: true,
  pendingRewardsFunctionName: "pendingSynapse", // used for rewardsAvailable(), use correct function name from masterchef
};

async function main() {
  if (
    Object.values(vaultParams).some(v => v === undefined) ||
    Object.values(strategyParams).some(v => v === undefined)
  ) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  console.log("Creating vault from V7 factory");
  const factory = await ethers.getContractAt(vaultV7Factory.abi, strategyParams.beefyVaultProxy);
  const vaultAddress = await factory.callStatic.cloneVault();
  let tx = await factory.cloneVault();
  tx = await tx.wait();
  tx.status === 1
    ? console.log(`Vault ${vaultAddress} is deployed with tx: ${tx.transactionHash}`)
    : console.log(`Vault ${vaultAddress} deploy failed with tx: ${tx.transactionHash}`);
  const vaultContract = await ethers.getContractAt(vaultV7.abi, vaultAddress);

  console.log("Strategy factory init");
  const StrategyFactory = await ethers.getContractFactory(strategyParams.strategyContractName);
  console.log("Deploying strategy");
  const strategyContract = await StrategyFactory.deploy();
  await strategyContract.deployed();
  console.log(`Strategy deployed at ${strategyContract.address}`);

  // initializing
  const strategyInitArguments = [
    strategyParams.want,
    strategyParams.poolId,
    strategyParams.chef,
    [
      vaultAddress,
      strategyParams.unirouter,
      strategyParams.keeper,
      strategyParams.strategist,
      strategyParams.beefyFeeRecipient,
      strategyParams.beefyFeeConfig,
    ],
    strategyParams.outputToNativeRoute,
    strategyParams.outputToLp0Route,
    strategyParams.outputToLp1Route,
  ];
  console.log(`Initializing strategy contract`);
  let strategyInitTx = await strategyContract.initialize(...strategyInitArguments);
  strategyInitTx = await strategyInitTx.wait();
  strategyInitTx.status === 1
    ? console.log(`Strategy Intilization done with tx: ${strategyInitTx.transactionHash}`)
    : console.log(`Strategy Intilization failed with tx: ${strategyInitTx.transactionHash}`);

  const vaultInitArguments = [strategyContract.address, vaultParams.mooName, vaultParams.mooSymbol, vaultParams.delay];
  console.log(`Initializing vault contract`);
  let vaultInitTx = await vaultContract.initialize(...vaultInitArguments);
  vaultInitTx = await vaultInitTx.wait();
  vaultInitTx.status === 1
    ? console.log(`Vault Intilization done with tx: ${vaultInitTx.transactionHash}`)
    : console.log(`Vault Intilization failed with tx: ${vaultInitTx.transactionHash}`);

  // ownership

  vaultInitTx = await vaultContract.transferOwnership(beefyfinance.vaultOwner);
  vaultInitTx = await vaultInitTx.wait();
  vaultInitTx.status === 1
    ? console.log(`Vault OwnershipTransfered done with tx: ${vaultInitTx.transactionHash}`)
    : console.log(`Vault Intilization failed with tx: ${vaultInitTx.transactionHash}`);

  // add this info to PR
  console.log();
  console.log("Vault:", vaultContract.address);
  console.log("Strategy:", strategyContract.address);
  console.log("Want:", strategyParams.want);
  console.log("PoolId:", strategyParams.poolId);

  console.log();
  console.log("Running post deployment");

  const verifyContractsPromises: Promise<any>[] = [];
  if (shouldVerifyOnEtherscan) {
    // skip await as this is a long running operation, and you can do other stuff to prepare vault while this finishes
    verifyContractsPromises.push(
      verifyContract(vaultContract.address, vaultInitArguments),
      verifyContract(strategyContract.address, strategyInitArguments)
    );
  }

  if (strategyParams.shouldSetPendingRewardsFunctionName) {
    await setPendingRewardsFunctionName(strategyContract, strategyParams.pendingRewardsFunctionName);
  }

  await Promise.all(verifyContractsPromises);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
