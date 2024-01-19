import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { setPendingRewardsFunctionName } from "../utils/setPendingRewardsFunctionName";
import vaultV7 from "../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";
// Change abi import if initialization arguments are different to the common chef strategy
import stratAbi from "../artifacts/contracts/BIFI/strategies/Common/StrategyCommonChefLP.sol/StrategyCommonChefLP.json";

const {
  platforms: { pancake, beefyfinance },
  tokens: {
    CAKE: { address: CAKE }, // This pulls the addresses from the address book, new tokens will probably not be in there yet.
    WBNB: { address: WBNB },
    BUSD: { address: BUSD },
  },
} = addressBook.bsc;

const want = web3.utils.toChecksumAddress("0x0eD7e52944161450477ee417DE9Cd3a859b14fD0"); // Add the address of the underlying LP.

const vaultParams = {
  mooName: "Moo CakeV2 CAKE-BNB", // Update the mooName, "Moo" + Platform name + token0-token1.
  mooSymbol: "mooCakeV2CAKE-BNB", // Update the mooSymbol (no spaces and lower case m at start).
};

const contractNames = {
  strategy: "StrategyCommonChefLP", // Add the strategy name to determine which strategy to deploy.
};

const strategyParams = {
  want: want, // Want is the address entered above
  poolId: 2, // Add the poolId.
  chef: pancake.masterchefV2, // Pulled from address book automatically
  outputToNativeRoute: [CAKE, WBNB], // Add the route to convert from the reward token to the native token.
  outputToLp0Route: [CAKE, CAKE], // Add the route to convert your reward token to token0 (token0 found on the want contract)
  outputToLp1Route: [CAKE, WBNB], // Add the route to convert your reward token to token1 (token1 found on want contract)
  unirouter: pancake.router, // Pulled from address book automatically

  shouldSetPendingRewardsFunctionName: true, // Not always needed if pending rewards is hardcoded on strategy
  pendingRewardsFunctionName: "pendingCake", // Different for each platform
  strategyImplementation: "", // Add existing implementation if it already exists (cheaper deployments)

  strategist: process.env.STRATEGIST_ADDRESS, // Add your public address or pull it from the .env file.
  keeper: beefyfinance.keeper, // Pulled from address book automatically
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient, // Pulled from address book automatically
  beefyFeeConfig: beefyfinance.beefyFeeConfig, // Pulled from address book automatically
  beefyVaultProxy: beefyfinance.vaultFactory, // Pulled from the address book automatically
};

async function main() {
  // check for undefined values
  if (
    Object.values(vaultParams).some(v => v === undefined) ||
    Object.values(strategyParams).some(v => v === undefined) ||
    Object.values(contractNames).some(v => v === undefined)
  ) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  console.log("Deploying:", vaultParams.mooName);

  // clone an empty vault
  const factory = await ethers.getContractAt(vaultV7Factory.abi, strategyParams.beefyVaultProxy);
  let vault = await factory.callStatic.cloneVault();
  let tx = await factory.cloneVault();
  tx = await tx.wait();
  tx.status === 1
  ? console.log(`Vault ${vault} is deployed with tx: ${tx.transactionHash}`)
  : console.log(`Vault ${vault} deploy failed with tx: ${tx.transactionHash}`);

  let strat = "";
  if (strategyParams.strategyImplementation != "") {
    // clone an existing strategy implementation
    strat = await factory.callStatic.cloneContract(strategyParams.strategyImplementation);
    let stratTx = await factory.cloneContract(strategyParams.strategyImplementation);
    stratTx = await stratTx.wait();
    stratTx.status === 1
    ? console.log(`Strat ${strat} is deployed with tx: ${stratTx.transactionHash}`)
    : console.log(`Strat ${strat} deploy failed with tx: ${stratTx.transactionHash}`);
  } else {
    // deploy a new strategy
    const Strategy = await ethers.getContractFactory(contractNames.strategy);
    const strategy = await Strategy.deploy();
    await strategy.deployed();
    strat = strategy.address;
    console.log("Strategy deployed to:", strat);
  }

  // no change needed by deployer
  const vaultConstructorArguments = [
    strat,
    vaultParams.mooName,
    vaultParams.mooSymbol,
    21600,
  ];

  // initialize the vault
  const vaultContract = await ethers.getContractAt(vaultV7.abi, vault);
  let vaultInitTx = await vaultContract.initialize(...vaultConstructorArguments);
  vaultInitTx = await vaultInitTx.wait()
  vaultInitTx.status === 1
  ? console.log(`Vault Initialization done with tx: ${vaultInitTx.transactionHash}`)
  : console.log(`Vault Initialization failed with tx: ${vaultInitTx.transactionHash}`);

  // transfer over vault ownership, deployer doesn't need it at any point
  vaultInitTx = await vaultContract.transferOwnership(beefyfinance.vaultOwner);
  vaultInitTx = await vaultInitTx.wait()
  vaultInitTx.status === 1
  ? console.log(`Vault OwnershipTransfered done with tx: ${vaultInitTx.transactionHash}`)
  : console.log(`Vault OwnershipTransfered failed with tx: ${vaultInitTx.transactionHash}`);

  // change the order to match strategy if required
  const strategyConstructorArguments = [
    strategyParams.want,
    strategyParams.poolId,
    strategyParams.chef,
    strategyParams.outputToNativeRoute,
    strategyParams.outputToLp0Route,
    strategyParams.outputToLp1Route,
    [
      vault,
      strategyParams.unirouter,
      strategyParams.keeper,
      strategyParams.strategist,
      strategyParams.beefyFeeRecipient,
      strategyParams.beefyFeeConfig,
    ],
  ];

  // initialize the strategy
  const stratContract = await ethers.getContractAt(stratAbi.abi, strat);
  let stratInitTx = await stratContract.initialize(...strategyConstructorArguments);
  stratInitTx = await stratInitTx.wait()
  stratInitTx.status === 1
  ? console.log(`Strat Initialization done with tx: ${stratInitTx.transactionHash}`)
  : console.log(`Strat Initialization failed with tx: ${stratInitTx.transactionHash}`);

  // add this info to PR
  console.log();
  console.log("Vault:", vault);
  console.log("Strategy:", strat);
  console.log("Want:", strategyParams.want);
  console.log("PoolId:", strategyParams.poolId);

  console.log();
  console.log("Running post deployment");

  // set the pending reward function if needed
  if (strategyParams.shouldSetPendingRewardsFunctionName) {
    await setPendingRewardsFunctionName(stratContract, strategyParams.pendingRewardsFunctionName);
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
