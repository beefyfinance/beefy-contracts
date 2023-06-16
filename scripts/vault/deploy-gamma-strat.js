import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import vaultV7 from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";
import stratAbi from "../../artifacts/contracts/BIFI/strategies/Gamma/StrategyThenaGamma.sol/StrategyThenaGamma.json";
import stratChefAbi from "../../artifacts/contracts/BIFI/strategies/Gamma/StrategyQuickGamma.sol/StrategyQuickGamma.json";


const {
  platforms: { quickswap, beefyfinance },
  tokens: {
    ETH: {address: ETH},
    USDC: {address: USDC},
    MATIC: {address: MATIC},
    WBTC: {address: WBTC},
    USDT: { address: USDT},
    newQUICK: {address: newQUICK},
    MaticX: { address: MaticX },
    stMATIC: { address: stMATIC },
    SD: {address: SD}
  },
} = addressBook.polygon;


const want = web3.utils.toChecksumAddress("0x4A83253e88e77E8d518638974530d0cBbbF3b675");
const rewardPool = web3.utils.toChecksumAddress("0x2a2d5Fc3793019C71ce94a07B85659943b832E41");

const vaultParams = {
  mooName: "Moo Quick MATIC-USDC Wide",
  mooSymbol: "mooQuickMATIC-USDCWide",
  delay: 21600,
};

const strategyParams = {
  want: want,
  rewardPool: rewardPool,
  chef: "0x20ec0d06F447d550fC6edee42121bc8C1817b97D",
  pid: 3,
  unirouter: web3.utils.toChecksumAddress("0xf5b509bB0909a69B1c207E495f687a596C168E12"),
  strategist: process.env.STRATEGIST_ADDRESS, // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  feeConfig: beefyfinance.beefyFeeConfig,
  outputToNativeRoute: ethers.utils.solidityPack(["address", "address"], [newQUICK, MATIC]),
  outputToLp0Route: '0x', //ethers.utils.solidityPack(["address"], [MATIC]),
  outputToLp1Route: ethers.utils.solidityPack(["address", "address"], [MATIC, USDC]),
  verifyStrat: false,
  beefyVaultProxy: beefyfinance.vaultFactory,
  strategyImplementation: "0xf0e7f344AA64bB581A90F32FC3aCBa8D1Dd14e89",
  strategyChefImplementation: "0x5Dda0D7ef00E0b3A30EDf9Ab1132D463d7A0b355",
  useVaultProxy: true,
  chefStrat: true,
  addReward: false, 
  rewardToken: SD, 
  rewardPath: ethers.utils.solidityPack(["address", "address", "address"], [SD, USDC, MATIC])
 // ensId
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

  console.log("Deploying:", vaultParams.mooName);

  const factory = await ethers.getContractAt(vaultV7Factory.abi, strategyParams.beefyVaultProxy);
  let vault = await factory.callStatic.cloneVault();
  let tx = await factory.cloneVault();
  tx = await tx.wait();
  tx.status === 1
  ? console.log(`Vault ${vault} is deployed with tx: ${tx.transactionHash}`)
  : console.log(`Vault ${vault} deploy failed with tx: ${tx.transactionHash}`);

  let implementation = strategyParams.chefStrat ? strategyParams.strategyChefImplementation : strategyParams.strategyImplementation;
  let strat = await factory.callStatic.cloneContract(implementation);
  let stratTx = await factory.cloneContract(implementation);
  stratTx = await stratTx.wait();
  stratTx.status === 1
  ? console.log(`Strat ${strat} is deployed with tx: ${stratTx.transactionHash}`)
  : console.log(`Strat ${strat} deploy failed with tx: ${stratTx.transactionHash}`);

  const vaultConstructorArguments = [
    strat,
    vaultParams.mooName,
    vaultParams.mooSymbol,
    vaultParams.delay,
  ];

  const vaultContract = await ethers.getContractAt(vaultV7.abi, vault);
  let vaultInitTx = await vaultContract.initialize(...vaultConstructorArguments);
  vaultInitTx = await vaultInitTx.wait()
  vaultInitTx.status === 1
  ? console.log(`Vault Intilization done with tx: ${vaultInitTx.transactionHash}`)
  : console.log(`Vault Intilization failed with tx: ${vaultInitTx.transactionHash}`);

  vaultInitTx = await vaultContract.transferOwnership(beefyfinance.vaultOwner);
  vaultInitTx = await vaultInitTx.wait()
  vaultInitTx.status === 1
  ? console.log(`Vault OwnershipTransfered done with tx: ${vaultInitTx.transactionHash}`)
  : console.log(`Vault Intilization failed with tx: ${vaultInitTx.transactionHash}`);

  const strategyConstructorArguments = [
    strategyParams.want,
    strategyParams.rewardPool,
    strategyParams.outputToNativeRoute,
    strategyParams.outputToLp0Route, 
    strategyParams.outputToLp1Route,
    [
        vault,
        strategyParams.unirouter,
        strategyParams.keeper,
        strategyParams.strategist,
        strategyParams.beefyFeeRecipient,
        strategyParams.feeConfig,
    ]
  ];

  const strategyChefConstructorArguments = [
    strategyParams.want,
    strategyParams.chef,
    strategyParams.pid,
    strategyParams.outputToNativeRoute,
    strategyParams.outputToLp0Route, 
    strategyParams.outputToLp1Route,
    [
        vault,
        strategyParams.unirouter,
        strategyParams.keeper,
        strategyParams.strategist,
        strategyParams.beefyFeeRecipient,
        strategyParams.feeConfig,
    ]
  ];

  let abi = strategyParams.chefStrat ? stratChefAbi.abi : stratAbi.abi;
  const stratContract = await ethers.getContractAt(abi, strat);
  let args = strategyParams.chefStrat ? strategyChefConstructorArguments : strategyConstructorArguments
  let stratInitTx = await stratContract.initialize(...args);
  stratInitTx = await stratInitTx.wait()
  stratInitTx.status === 1
  ? console.log(`Strat Intilization done with tx: ${stratInitTx.transactionHash}`)
  : console.log(`Strat Intilization failed with tx: ${stratInitTx.transactionHash}`);

  if (strategyParams.addReward) {
    stratInitTx = await stratContract.addReward(strategyParams.rewardToken, strategyParams.rewardPath);
    stratInitTx = await stratInitTx.wait()
    stratInitTx.status === 1
    ? console.log(`Adding Rewards done with tx: ${stratInitTx.transactionHash}`)
    : console.log(`Adding Reward failed with tx: ${stratInitTx.transactionHash}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });