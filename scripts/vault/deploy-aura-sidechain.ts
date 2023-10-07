import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import vaultV7 from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";
import stratAbi from "../../artifacts/contracts/BIFI/strategies/Balancer/StrategyAuraSideChainOmnichainSwap.sol/StrategyAuraSideChainOmnichainSwap.json"

const {
  platforms: { beethovenX, beefyfinance },
  tokens: {
    BAL: { address: BAL },
    ETH: { address: ETH },
    opUSDCe: { address: opUSDCe },
    DOLA: { address: DOLA },
    OP: { address: OP },
    
  },
} = addressBook.optimism;

const AURA = "0x1509706a6c66CA549ff0cB464de88231DDBe213B";

const bytes0 = '0x0000000000000000000000000000000000000000000000000000000000000000';

const booster = web3.utils.toChecksumAddress("0x98Ef32edd24e2c92525E59afc4475C1242a30184");
const want = web3.utils.toChecksumAddress("0xACfE9b4782910A853b68abbA60f3FD8049Ffe638");

const vaultParams = {
  mooName: "Moo Aura OP DOLA/USDCe",
  mooSymbol: "mooAuraOPDOLA/USDCe",
  delay: 21600,
};

const strategyParams = {
  want: want,
  booster: booster,
  pid: 9,
  input: want,
  isComposable: true,
  composable: true,
  unirouter: beethovenX.router,
  strategist: process.env.STRATEGIST_ADDRESS,
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  beefyFeeConfig: beefyfinance.beefyFeeConfig,
  beefyVaultProxy: beefyfinance.vaultFactory,
  strategyImplementation: "0x16Ab7178b1B062A326C007a52E32A67218151b59",
  swapper: "0x98Cbcd43f28bc0a7Bf058191dBe3AD3bD9B49FE6",
  useVaultProxy: true,
  outputToNativeAssets: [
    BAL, 
    OP,
    ETH
  ],
  outputToNativeRouteBytes: [
        [
            "0xd6e5824b54f64ce6f1161210bc17eebffc77e031000100000000000000000006",
            0,
            1
        ],
        [
            "0x39965c9dab5448482cf7e002f583c812ceb53046000100000000000000000003",
            1,
            2
        ]
    ],
  nativeToInputAssets: [
    ETH,
    opUSDCe,
    want
  ],
  nativeToInputRouteBytes: [
        [
            "0x39965c9dab5448482cf7e002f583c812ceb53046000100000000000000000003",
            0,
            1
        ],
        [
          "0xacfe9b4782910a853b68abba60f3fd8049ffe6380000000000000000000000ff",
          1,
          2
      ]
    ],
    extraToNativeAssets: [OP, ETH],
    extraToNativePath: [
        [
            "0x39965c9dab5448482cf7e002f583c812ceb53046000100000000000000000003",
            0,
            1
        ]
    ]
}

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
  let stratTx = await factory.cloneContract(strategyParams.strategyImplementation);
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
    AURA,
    strategyParams.isComposable,
    strategyParams.nativeToInputRouteBytes,
    strategyParams.outputToNativeRouteBytes,
    strategyParams.booster,
    strategyParams.swapper,
    strategyParams.pid,
    strategyParams.nativeToInputAssets,
    strategyParams.outputToNativeAssets,
    [vault,
    strategyParams.unirouter,
    strategyParams.keeper,
    strategyParams.strategist,
    strategyParams.beefyFeeRecipient,
    strategyParams.beefyFeeConfig],
  ];

  //console.log(...strategyConstructorArguments);

  const stratContract = await ethers.getContractAt( stratAbi.abi, strat);
  const args =  strategyConstructorArguments;
  let stratInitTx = await stratContract.initialize(...args);
  stratInitTx = await stratInitTx.wait()
  stratInitTx.status === 1
  ? console.log(`Strat Intilization done with tx: ${stratInitTx.transactionHash}`)
  : console.log(`Strat Intilization failed with tx: ${stratInitTx.transactionHash}`);

  stratInitTx = await stratContract.addRewardToken(AURA, strategyParams.extraToNativePath, strategyParams.extraToNativeAssets, bytes0, 100);
  stratInitTx = await stratInitTx.wait()
  stratInitTx.status === 1
  ? console.log(`Aura Reward Added with tx: ${stratInitTx.transactionHash}`)
  : console.log(`Aura Reward Addition failed with tx: ${stratInitTx.transactionHash}`);
  // add this info to PR

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });