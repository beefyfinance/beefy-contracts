import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import vaultV7 from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";
import stratAbi from "../../artifacts/contracts/BIFI/strategies/Balancer/StrategyAuraMainnet.sol/StrategyAuraMainnet.json"
import stratGryoAbi from "../../artifacts/contracts/BIFI/strategies/Balancer/StrategyAuraGyroMainnet.sol/StrategyAuraGyroMainnet.json";

const {
  platforms: { balancer, beefyfinance },
  tokens: {
    BAL: { address: BAL },
    ETH: { address: ETH },
    cbETH: { address: cbETH },
    wstETH: { address: wstETH },
    AURA: { address: AURA },
    R: { address: R },
    sDAI: { address: sDAI },
    DAI: { address: DAI },
    USDC: { address: USDC },
    
  },
} = addressBook.ethereum;

const bytes0 = '0x0000000000000000000000000000000000000000000000000000000000000000';

const booster = web3.utils.toChecksumAddress("0xA57b8d98dAE62B26Ec3bcC4a365338157060B234");
const want = web3.utils.toChecksumAddress("0x8353157092ED8Be69a9DF8F95af097bbF33Cb2aF");

const vaultParams = {
  mooName: "Moo Aura GHO/USDC/USDT",
  mooSymbol: "mooAuraGHO/USDC/USDT",
  delay: 21600,
};

const strategyParams = {
  want: want,
  booster: booster,
  pid: 157,
  input: want,
  isComposable: true,
  composable: true,
  unirouter: balancer.router,
  strategist: process.env.STRATEGIST_ADDRESS,
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  beefyFeeConfig: beefyfinance.beefyFeeConfig,
  beefyVaultProxy: "0xC551dDCE8e5E657503Cd67A39713c06F2c0d2e97", //beefyfinance.vaultProxy,
  strategyImplementation: "0xfa9C83b68269EB996DF895B18Ab62b9d4F46857c",
  stratgeyGyroImplementation: "0x2b494952C10632B11fEf3139C38fE2AD939F4243",
  useVaultProxy: true,
  gyroStrat: false,
  outputToNativeAssets: [
    BAL, 
    ETH
  ],
  outputToNativeRouteBytes: [
        [
            "0x5c6ee304399dbdb9c8ef030ab642b10820db8f56000200000000000000000014",
            0,
            1
        ]  
    ],
  nativeToLp0Assets: [
    ETH,
    USDC,
    want
  ],
  nativeToLp0RouteBytes: [
        [
            "0x96646936b91d6b9d7d0c47c496afbf3d6ec7b6f8000200000000000000000019",
            0,
            1
        ],
        [
          "0x8353157092ed8be69a9df8f95af097bbf33cb2af0000000000000000000005d9",
          1,
          2
      ]
    ],
    lp0ToLp1Assets: [
      R,
      sDAI
    ],
    lp0ToLp1RouteBytes: [
          [
              "0x93d199263632a4ef4bb438f1feb99e57b4b5f0bd0000000000000000000005c2",
              0,
              1
          ]
      ],
    auraToNativeAssets: [AURA, ETH],
    auraToNativePath: [
        [
            "0xc29562b045d80fd77c69bec09541f5c16fe20d9d000200000000000000000251",
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
/*
  const factory = await ethers.getContractAt(vaultV7Factory.abi, strategyParams.beefyVaultProxy);
  let vault = await factory.callStatic.cloneVault();
  let tx = await factory.cloneVault();
  tx = await tx.wait();
  tx.status === 1
  ? console.log(`Vault ${vault} is deployed with tx: ${tx.transactionHash}`)
  : console.log(`Vault ${vault} deploy failed with tx: ${tx.transactionHash}`);

  let strat = await factory.callStatic.cloneContract(strategyParams.gyroStrat ? strategyParams.stratgeyGyroImplementation : strategyParams.strategyImplementation);
  let stratTx = await factory.cloneContract(strategyParams.gyroStrat ? strategyParams.stratgeyGyroImplementation : strategyParams.strategyImplementation);
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
*/
const vault = "0x234Fd76985dA4fD505DbAF7A48e119Cd5dFD5C8F";
const strat = "0xA08F6dE8D72AF1dC857b40E910524CAd883538CC";
  const strategyConstructorArguments = [
    strategyParams.want,
    strategyParams.isComposable,
    strategyParams.nativeToLp0RouteBytes,
    strategyParams.outputToNativeRouteBytes,
    strategyParams.booster,
    strategyParams.pid,
    strategyParams.composable,
    strategyParams.nativeToLp0Assets,
    strategyParams.outputToNativeAssets,
    [vault,
    strategyParams.unirouter,
    strategyParams.keeper,
    strategyParams.strategist,
    strategyParams.beefyFeeRecipient,
    strategyParams.beefyFeeConfig],
  ];


  const strategyGyroConstructorArguments = [
    strategyParams.want,
    strategyParams.nativeToLp0RouteBytes,
    strategyParams.lp0ToLp1RouteBytes,
    strategyParams.outputToNativeRouteBytes,
    strategyParams.booster,
    strategyParams.pid,
    strategyParams.nativeToLp0Assets,
    strategyParams.lp0ToLp1Assets,
    strategyParams.outputToNativeAssets,
    [vault,
    strategyParams.unirouter,
    strategyParams.keeper,
    strategyParams.strategist,
    strategyParams.beefyFeeRecipient,
    strategyParams.beefyFeeConfig],
  ];

  //console.log(...strategyConstructorArguments);

  const stratContract = await ethers.getContractAt(strategyParams.gyroStrat ? stratGryoAbi.abi : stratAbi.abi, strat);
  const args = strategyParams.gyroStrat ? strategyGyroConstructorArguments : strategyConstructorArguments;
  let stratInitTx = await stratContract.initialize(...args);
  stratInitTx = await stratInitTx.wait()
  stratInitTx.status === 1
  ? console.log(`Strat Intilization done with tx: ${stratInitTx.transactionHash}`)
  : console.log(`Strat Intilization failed with tx: ${stratInitTx.transactionHash}`);

  stratInitTx = await stratContract.addRewardToken(AURA, strategyParams.auraToNativePath, strategyParams.auraToNativeAssets, bytes0, 100);
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