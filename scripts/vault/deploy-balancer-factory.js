import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import vaultV7 from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";
import strategyFactory from "../../artifacts/contracts/BIFI/infra/StrategyFactory.sol/StrategyFactory.json"
import stratAbi from "../../artifacts/contracts/BIFI/strategies/Balancer/StrategyBalancer.sol/StrategyBalancer.json";

const {
  platforms: { beefyfinance, balancer },
  tokens: {
    USDC: { address: USDC },
    BAL: { address: BAL },
    AURA: { address: AURA }
  },
} = addressBook.arbitrum;


const want = web3.utils.toChecksumAddress("0x4284c68f567903537E2d9Ff726fdF8591E431DDC");
const gauge = web3.utils.toChecksumAddress(ethers.constants.AddressZero);
const booster = web3.utils.toChecksumAddress("0x98Ef32edd24e2c92525E59afc4475C1242a30184");

const platform = "Balancer";
const tokens = ["MORE", "GYD"]
const tokensCombined = "MORE/GYD";
const chain = "Base";
const id = "aura-arb-more-gyd";

const vaultParams = {
  mooName: "Moo " + platform + " " + chain + " " + tokensCombined,
  mooSymbol: "moo" + platform + chain + tokensCombined,
  delay: 21600,
};

const strategyParams = {
  want: want,
  gauge: gauge,
  booster: booster,
  pid: 90, // If using balancer instead of Aura set PID to 1234567
  swapper: beefyfinance.beefySwapper,
  balancerVault: balancer.router,
  depositToken: want,
  strategist: "0x79c6d6834511703569845711a60C60c21A2dbB9b", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  feeConfig: beefyfinance.beefyFeeConfig,
  verifyStrat: false,
  rewards: [BAL, AURA, USDC],
  beefyVaultProxy: beefyfinance.vaultFactory,
  stratFactory: beefyfinance.strategyFactory,
  strategyImplementationName: "StrategyBalancerGyro",
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