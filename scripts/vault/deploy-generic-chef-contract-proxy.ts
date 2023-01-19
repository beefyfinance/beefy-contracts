import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import vaultV7 from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";
import stratAbiEth from "../../artifacts/contracts/BIFI/strategies/Common/StrategyCommonChefLPProxySweeper.sol/StrategyCommonChefLPProxySweeper.json";
import stratAbi from "../../artifacts/contracts/BIFI/strategies/Common/StrategyCommonChefLPProxy.sol/StrategyCommonChefLPProxy.json";

const {
  platforms: { sushi, synapse, beefyfinance },
  tokens: {
    LDO: { address: LDO },
    SUSHI: { address: SUSHI },
    ETH: { address: ETH },
    USDC: { address: USDC }
  },
} = addressBook.ethereum;


const want = web3.utils.toChecksumAddress("0x397FF1542f962076d0BFE58eA045FfA2d347ACa0");
const ensId = ethers.utils.formatBytes32String("cake.eth");

const vaultParams = {
  mooName: "Moo Sushi ETH-USDC",
  mooSymbol: "mooSushiETH-USDC",
  delay: 21600,
};

const strategyParams = {
  want: want,
  poolId: 1,
  chef: sushi.masterchef,
  unirouter: sushi.router,
  strategist: process.env.STRATEGIST_ADDRESS,
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  beefyFeeConfig: beefyfinance.beefyFeeConfig,
  outputToNativeRoute: [SUSHI, ETH],
  outputToLp0Route: [SUSHI, ETH, USDC],
  outputToLp1Route: [SUSHI, ETH],
  beefyVaultProxy: beefyfinance.vaultFactory,  //beefyfinance.vaultProxy,
  strategyImplementation: "0xe900d8b8F562CEB2B56b944Dabf64d285b1faFcA",
  strategyMainnetImplementation: "0xe900d8b8F562CEB2B56b944Dabf64d285b1faFcA",
  useVaultProxy: true,
  isMainnetVault: true,
  ensId,
  shouldSetPendingRewardsFunctionName: true,
  pendingRewardsFunctionName: "pendingSushi", // used for rewardsAvailable(), use correct function name from masterchef
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

  let strat = await factory.callStatic.cloneContract(strategyParams.isMainnetVault ? strategyParams.strategyMainnetImplementation : strategyParams.strategyImplementation);
  let stratTx = await factory.cloneContract(strategyParams.isMainnetVault ? strategyParams.strategyMainnetImplementation : strategyParams.strategyImplementation);
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
    strategyParams.poolId,
    strategyParams.chef,
    [vault,
    strategyParams.unirouter,
    strategyParams.keeper,
    strategyParams.strategist,
    strategyParams.beefyFeeRecipient,
    strategyParams.beefyFeeConfig],
    strategyParams.outputToNativeRoute,
    strategyParams.outputToLp0Route,
    strategyParams.outputToLp1Route
  ];

  let abi = strategyParams.isMainnetVault ? stratAbiEth.abi : stratAbi.abi;
  const stratContract = await ethers.getContractAt(abi, strat);
  let args = strategyConstructorArguments
  let stratInitTx = await stratContract.initialize(...args);
  stratInitTx = await stratInitTx.wait()
  stratInitTx.status === 1
  ? console.log(`Strat Intilization done with tx: ${stratInitTx.transactionHash}`)
  : console.log(`Strat Intilization failed with tx: ${stratInitTx.transactionHash}`);

  stratInitTx = await stratContract.setPendingRewardsFunctionName(strategyParams.pendingRewardsFunctionName);
  stratInitTx = await stratInitTx.wait()
  stratInitTx.status === 1
  ? console.log(`Pending Reward Name Set with tx: ${stratInitTx.transactionHash}`)
  : console.log(`Pending Reward Name Set with tx: ${stratInitTx.transactionHash}`);
}


main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });