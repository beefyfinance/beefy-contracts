import hardhat, { ethers } from "hardhat";
import { addressBook } from "@beefyfinance/blockchain-addressbook";
import vaultV7 from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";
import strategyFactory from "../../artifacts/contracts/BIFI/infra/StrategyFactory.sol/StrategyFactory.json"
import stratAbi from "../../artifacts/contracts/BIFI/strategies/Tokemak/StrategyTokemak.sol/StrategyTokemak.json";
import { getAddress } from "viem";

const {
  platforms: { beefyfinance },
  tokens: {
    TOKE: { address: TOKE }
  },
} = addressBook.ethereum;


const want = getAddress("0xE800e3760FC20aA98c5df6A9816147f190455AF3");
const rewardPool = getAddress("0x9597C17f323160D8462c194D72FAAcF7b4CBCd2b");

const platform = "Tokemak";
const tokens = "autoLRT";
const chain = "Eth";
const id = "tokemak-autolrt";

const vaultParams = {
  mooName: "Moo " + platform + " " + chain + " " + tokens,
  mooSymbol: "moo" + platform + chain + tokens,
  delay: 21600,
};

const strategyParams = {
  want: want,
  rewardPool: rewardPool,
  swapper: beefyfinance.beefySwapper,
  strategist: "0x79c6d6834511703569845711a60C60c21A2dbB9b", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  feeConfig: beefyfinance.beefyFeeConfig,
  verifyStrat: false,
  rewards: [TOKE],
  beefyVaultProxy: beefyfinance.vaultFactory,
  stratFactory: "0x52941De3eDE234ae6B8608597440Ac3394C64Ae8",
  strategyImplementationName: "Tokemak_V2",
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
    "name": "${tokens}",
    "type": "standard",
    "token": "${tokens}",
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
    "assets": ["${tokens}"],
    "risks": ["COMPLEXITY_HIGH", "BATTLE_TESTED", "IL_HIGH", "MCAP_LARGE", "CONTRACTS_VERIFIED"],
    "strategyTypeId": "multi-lp",
    "addLiquidityUrl": "https://app.tokemak.xyz/autopool?id=${want}",
    "network": "ethereum"
  },
    `)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });