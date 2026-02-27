import hardhat, { ethers } from "hardhat";
import { addressBook } from "@beefyfinance/blockchain-addressbook";
import vaultV7 from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";
import strategyFactory from "../../artifacts/contracts/BIFI/infra/StrategyFactory.sol/StrategyFactory.json"
import stratAbi from "../../artifacts/contracts/BIFI/strategies/Velodrome/StrategyVelodromeFactory.sol/StrategyVelodromeFactory.json";
import { getAddress } from "viem";

const {
  platforms: { beefyfinance, equalizer },
  tokens: {
    //ETH: { address: ETH },
   // USDCe: { address: USDCe },
    EQUAL: { address: EQUAL },
  },
} = addressBook.sonic;

const BRUSH = "0xE51EE9868C1f0d6cd968A8B8C8376Dc2991BFE44";
const stS = "0xE5DA20F15420aD15DE0fa650600aFc998bbE3955";
const scUSD = "0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE";

const want = getAddress("0xB78CdF29F7E563ea447feBB5b48DDe9bC3278Ba4");
const rewardPool = getAddress("0x8c030811a8C5E1890dAd1F5E581D28ac8740c532");

const platform = "Equalizer";
const tokens = ["scUSD", "USDC.e"]
const tokensCombined = tokens[0] + "-" + tokens[1];
const chain = "Sonic";
const id = "equalizer-sonic-usdc.e-scusd";

const vaultParams = {
  mooName: "Moo " + platform + " " + chain + " " + tokensCombined,
  mooSymbol: "moo" + platform + chain + tokensCombined,
  delay: 21600,
};

const strategyParams = {
  want: want,
  rewardPool: rewardPool,
  swapper: beefyfinance.beefySwapper,
  solidlyRouter: "0xED9d262985E18710DDDAC0dfC10a3f900679063B", //equalizer.router,
  strategist: "0xdad00eCa971D7B22e0dE1B874fbae30471B75354", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  feeConfig: beefyfinance.beefyFeeConfig,
  verifyStrat: false,
  rewards: [EQUAL],
  beefyVaultProxy: beefyfinance.vaultFactory,
  stratFactory: beefyfinance.strategyFactory,
  strategyImplementationName: "Equalizer",
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
    strategyParams.rewardPool,
    strategyParams.solidlyRouter,
    strategyParams.rewards,
    [
      strategyParams.want,
      ethers.constants.AddressZero,
      strategyParams.stratFactory,
      vault,
      strategyParams.swapper,
      strategyParams.strategist,
    ]
  ];

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
    "name": "${tokensCombined} vLP",
    "type": "standard",
    "token": "${tokensCombined} vLP",
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
    "addLiquidityUrl": "https://sonic.equalizer.exchange/liquidity/${want}",
    "network": "${chain.toLowerCase()}",
    "zaps": [
      {
        "strategyId": "solidly",
        "ammId": "sonic-equalizer"
      }
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