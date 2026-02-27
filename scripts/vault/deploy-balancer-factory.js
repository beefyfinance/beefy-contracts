import hardhat, { ethers } from "hardhat";
import { addressBook } from "@beefyfinance/blockchain-addressbook";
import vaultV7 from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";
import strategyFactory from "../../artifacts/contracts/BIFI/infra/StrategyFactory.sol/StrategyFactory.json"
import stratAbi from "../../artifacts/contracts/BIFI/strategies/Balancer/StrategyBalancer.sol/StrategyBalancer.json";
import { getAddress } from "viem";

const {
  platforms: { beefyfinance, balancer },
  tokens: {
   /* USDC: { address: USDC },
    BAL: { address: BAL },
    AURA: { address: AURA }*/
  },
} = addressBook.sonic;

const BEETS = "0x2D0E0814E62D80056181F5cd932274405966e4f0";

const want = getAddress("0x21FeD4063BF8ebf4F51f4ADF4ECFC9717aa4cA9D");
const gauge = getAddress("0xf6a0071f5607f589DF253E0991Ba6aBdDE7a6d32");
const booster = getAddress(ethers.constants.AddressZero);

const platform = "BeethovenX";
const tokens = ["BEETS", "stS", "LUDWIG"]
const tokensCombined = "BEETS/stS/LUDWIG";
const chain = "Sonic";
const id = "beets-sonic-high-speed-perfect-beets";

const vaultParams = {
  mooName: "Moo " + platform + " " + chain + " " + tokensCombined,
  mooSymbol: "moo" + platform + chain + tokensCombined,
  delay: 21600,
};

const strategyParams = {
  want: want,
  gauge: gauge,
  booster: booster,
  pid: 1234567, // If using balancer instead of Aura set PID to 1234567
  swapper: beefyfinance.beefySwapper,
  balancerVault: "0xBA12222222228d8Ba445958a75a0704d566BF2C8", //balancer.router,
  depositToken: want,
  strategist: "0xdad00eCa971D7B22e0dE1B874fbae30471B75354", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  feeConfig: beefyfinance.beefyFeeConfig,
  verifyStrat: false,
  rewards: [BEETS],
  beefyVaultProxy: beefyfinance.vaultFactory,
  stratFactory: beefyfinance.strategyFactory,
  strategyImplementationName: "BalancerV2",
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

  console.log(vaultParams, strategyParams)

  const factory = await ethers.getContractAt(vaultV7Factory.abi, strategyParams.beefyVaultProxy);
  const stratFactory = await ethers.getContractAt(strategyFactory.abi, strategyParams.stratFactory);
  let vault = await factory.callStatic.cloneVault();
  let tx = await factory.cloneVault();
  tx = await tx.wait();
  tx.status === 1
  ? console.log(`Vault ${vault} is deployed with tx: ${tx.transactionHash}`)
  : console.log(`Vault ${vault} deploy failed with tx: ${tx.transactionHash}`);

  let strat = await stratFactory.callStatic.createStrategy(strategyParams.strategyImplementationName);
  let stratTx = await stratFactory.createStrategy(strategyParams.strategyImplementationName);;
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
    strategyParams.gauge,
    strategyParams.booster,
    strategyParams.balancerVault,
    strategyParams.pid,
    strategyParams.rewards,
    [
      strategyParams.want,
      strategyParams.depositToken,
      strategyParams.stratFactory,
      vault,
      strategyParams.swapper,
      strategyParams.strategist,
    ]
  ];
  console.log(strategyConstructorArguments)

  let abi = stratAbi.abi;
  const stratContract = await ethers.getContractAt(abi, strat);
  let args =  strategyConstructorArguments
  let stratInitTx = await stratContract.initialize(...args);
  stratInitTx = await stratInitTx.wait()
  stratInitTx.status === 1
  ? console.log(`Strat Intilization done with tx: ${stratInitTx.transactionHash}`)
  : console.log(`Strat Intilization failed with tx: ${stratInitTx.transactionHash}`);

  console.log(` ---- V2 Blob -------`);
  console.log(`
{
    "id": "${id}",
    "name": "${tokensCombined} LP",
    "type": "standard",
    "token": "${tokensCombined} LP",
    "tokenAddress": "${want}",
    "tokenDecimals": 18,
    "tokenProviderId": "${platform.toLowerCase()}",
    "earnedToken": "${vaultParams.mooSymbol}",
    "earnedTokenAddress": "${vault}",
    "earnContractAddress": "${vault}",
    "oracle": "lps",
    "oracleId": "${id}",
    "createdAt": ${(Date.now() / 1000).toFixed(0)},
    "status": "active",
    "platformId": "${platform.toLowerCase()}",
    "assets": ["${tokens[0]}", "${tokens[1]}"],
    "risks": ["COMPLEXITY_LOW", "BATTLE_TESTED", "IL_HIGH", "MCAP_LARGE", "CONTRACTS_VERIFIED"],
    "strategyTypeId": "lp",
    "addLiquidityUrl": "",
    "network": "${chain.toLowerCase()}",
    "zaps": [
      
    ]
  },
    `)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });