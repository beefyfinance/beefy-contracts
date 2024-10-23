import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import vaultV7 from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";
import strategyFactory from "../../artifacts/contracts/BIFI/infra/StrategyFactory.sol/StrategyFactory.json"
import stratAbi from "../../artifacts/contracts/BIFI/strategies/Common/StrategySolidlyRewardPool.sol/StrategySolidlyRewardPool.json";
import { symbolName } from "typescript";

const {
  platforms: { beefyfinance },
  tokens: {
    TKN: { address: TKN }
  },
} = addressBook.scroll;


const want = web3.utils.toChecksumAddress("0x3513e7841f1DEA2141B433ba2A219E42b295efB2");
const rewardPool = web3.utils.toChecksumAddress("0x165c423935DdC3d0EF307909a5be32B8748FCF69");

const platform = "Tokan";
const tokens = ["WETH", "wrsETH"]
const tokensCombined = tokens[0] + "-" + tokens[1];
const chain = "Scroll";
const id = "tokan-weth-wrseth";

const vaultParams = {
  mooName: "Moo " + platform + " " + chain + " " + tokensCombined,
  mooSymbol: "moo" + platform + chain + tokensCombined,
  delay: 21600,
};

const strategyParams = {
  want: want,
  rewardPool: rewardPool,
  swapper: beefyfinance.beefySwapper,
  solidlyRouter: "0xA663c287b2f374878C07B7ac55C1BC927669425a",
  strategist: "0x79c6d6834511703569845711a60C60c21A2dbB9b", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  feeConfig: beefyfinance.beefyFeeConfig,
  verifyStrat: false,
  rewards: [TKN],
  beefyVaultProxy: beefyfinance.vaultFactory,
  stratFactory: "0x6F9989a4D84edb5068bD37Ee8c55C6E97d00c723",
  strategyImplementationName: "StrategyRewardPool",
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
    "addLiquidityUrl": "https://app.tokan.exchange/liquidity",
    "network": "${chain.toLowerCase()}",
    "zaps": [
      {
        "strategyId": "solidly",
        "ammId": "scroll-tokan"
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