import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import vaultV7 from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";
import stratAbi from "../../artifacts/contracts/BIFI/strategies/Common/StrategyCommonSolidlyRewardPool.sol/StrategyCommonSolidlyRewardPoolLP.json";
import stratStakerAbi from "../../artifacts/contracts/BIFI/strategies/Balancer/StrategyAuraBalancerComposableMultiRewardGaugeUniV3.sol/StrategyAuraBalancerComposableMultiRewardGaugeUniV3.json";

const {
  platforms: { thena, beefyfinance },
  tokens: {
    THE: {address: THE},
    USDC: { address: USDC },
    BUSD: {address: BUSD},
    BNB: {address: BNB}, 
    ETH: {address: ETH},
    MAI: {address: MAI},
    USDT: {address: USDT},
    BTCB: {address: BTCB},
    BNBx: {address: BNBx},
    FRAX: { address: FRAX},
    FXS: { address: FXS },
    HAY: { address: HAY }
  },
} = addressBook.bsc;


const want = web3.utils.toChecksumAddress("0x795065dCc9f64b5614C407a6EFDC400DA6221FB0");
const gauge = web3.utils.toChecksumAddress("0xE43317c1f037CBbaF33F33C386f2cAF2B6b25C9C");
const binSpiritGauge = web3.utils.toChecksumAddress("0x44e314190D9E4cE6d4C0903459204F8E21ff940A");
//const ensId = ethers.utils.formatBytes32String("cake.eth");

const vaultParams = {
  mooName: "Moo Thena HAY-BUSD",
  mooSymbol: "mooThenaHAY-BUSD",
  delay: 21600,
};

const strategyParams = {
  want: want,
  gauge: gauge,
  unirouter: thena.router,
  gaugeStaker: binSpiritGauge,
  strategist: process.env.STRATEGIST_ADDRESS, // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  feeConfig: beefyfinance.beefyFeeConfig,
  outputToNativeRoute: [[THE, BNB, false]],
  outputToLp0Route: [[THE, BUSD, false],[BUSD, HAY, true]],
  outputToLp1Route: [[THE, BUSD, false]],
  verifyStrat: false,
  spiritswapStrat: false,
  gaugeStakerStrat: false,
  beefyVaultProxy: "0xe596eC590DE52C09c8D1C7A1294B32F957A7c94e",  //beefyfinance.vaultProxy,
  strategyImplementation: "0xd1B5A6078B04b4BED9bF656b055c3721833972ba",
  strategyImplementationStaker: "0xC3d5c128a3e5b F60C6Fb87A4B644B6a2D8093f55",
  useVaultProxy: true,
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

  let strat = await factory.callStatic.cloneContract(strategyParams.strategyImplementation);
  let stratTx = await factory.cloneContract(strategyParams.gaugeStakerStrat ? strategyParams.strategyImplementationStaker : strategyParams.strategyImplementation);
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

  const strategyConstructorArgumentsStaker = [
    strategyParams.want,
    strategyParams.gauge,
    strategyParams.gaugeStaker,
    [
      vault,
      strategyParams.unirouter,
      strategyParams.keeper,
      strategyParams.strategist,
      strategyParams.beefyFeeRecipient,
      strategyParams.feeConfig,
    ],
    strategyParams.outputToNativeRoute,
    strategyParams.outputToLp0Route, 
    strategyParams.outputToLp1Route
  ];

  const strategyConstructorArguments = [
    strategyParams.want,
    strategyParams.gauge,
    [
      vault,
      strategyParams.unirouter,
      strategyParams.keeper,
      strategyParams.strategist,
      strategyParams.beefyFeeRecipient,
      strategyParams.feeConfig,
    ],
    strategyParams.outputToNativeRoute,
    strategyParams.outputToLp0Route, 
    strategyParams.outputToLp1Route
  ];

  let abi = strategyParams.gaugeStakerStrat  ? stratStakerAbi.abi : stratAbi.abi;
  const stratContract = await ethers.getContractAt(abi, strat);
  let args = strategyParams.gaugeStakerStrat  ? strategyConstructorArgumentsStaker : strategyConstructorArguments
  let stratInitTx = await stratContract.initialize(...args);
  stratInitTx = await stratInitTx.wait()
  stratInitTx.status === 1
  ? console.log(`Strat Intilization done with tx: ${stratInitTx.transactionHash}`)
  : console.log(`Strat Intilization failed with tx: ${stratInitTx.transactionHash}`);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });