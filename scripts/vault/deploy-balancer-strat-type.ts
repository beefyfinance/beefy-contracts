import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import vaultV7 from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";
import stratAbi from "../../artifacts/contracts/BIFI/strategies/Balancer/StrategyBalancerMultiRewardGaugeUniV3.sol/StrategyBalancerMultiRewardGaugeUniV3.json";
import stratComAbi from "../../artifacts/contracts/BIFI/strategies/Balancer/StrategyBalancerComposableMultiRewardGaugeUniV3.sol/StrategyBalancerComposableMultiRewardGaugeUniV3.json";

const {
  platforms: {  beefyfinance },
  tokens: {
    BAL: { address: BAL },
    //LDO: { address: LDO },
    wstETH: {address: wstETH },
    ETH: {address: ETH }
  },
} = addressBook.arbitrum;

const LDO = "0x13Ad51ed4F1B7e9Dc168d8a00cB3f4dDD85EfA60";

const bbrfBAL = "0xd0d334B6CfD77AcC94bAB28C7783982387856449";
const bbrfETH = "0xdd89c7cd0613c1557b2daac6ae663282900204f1";
const bbrfOP = "0xA4e597c1bD01859B393b124ce18427Aa4426A871";
const bbUSDplus = "0x88D07558470484c03d3bb44c3ECc36CAfCF43253";

const gauge = web3.utils.toChecksumAddress("0x251e51b25AFa40F2B6b9F05aaf1bC7eAa0551771");
const want = web3.utils.toChecksumAddress("0x36bf227d6bac96e2ab1ebb5492ecec69c691943f");

const vaultParams = {
  mooName: "Moo Balancer wstETH-ETH V2",
  mooSymbol: "mooBalancerwstETH-ETHV2",
  delay: 21600,
};

const bytes0 = '0x0000000000000000000000000000000000000000000000000000000000000000';
const rewardToNativeRouteBytes = ethers.utils.solidityPack(["address","int24","address"], [LDO, 10000, ETH]);

const strategyParams = {
  input: ETH,
  isComposable: false,
  unirouter: "0xBA12222222228d8Ba445958a75a0704d566BF2C8",//beethovenX.router,
  strategist: process.env.STRATEGIST_ADDRESS,
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  beefyFeeConfig: beefyfinance.beefyFeeConfig,
  isBeets: false,
  beefyVaultProxy: "0x8396f3d25d07531a80770Ce3DEA025932C4953f7",  //beefyfinance.vaultProxy,
  composableStrat: false,
  strategyImplementation: "0x06640459fDF9af5073048F8379d765F442C3daE9",
  comStrategyImplementation: "0x617B09c47c3918207fA154b7b789a8E5CDC1680A",
  useVaultProxy: true,
  extraReward: false, 
  secondExtraReward: true,
  outputToNativeAssets: [
    BAL,
    ETH
  ],
  outputToNativeRouteBytes: [
        [
            "0xcc65a812ce382ab909a11e434dbf75b34f1cc59d000200000000000000000001",
            0,
            1
        ]
    ],
  nativeToWantAssets: [
    ETH,
    ETH,
  ],
  nativeToWantRouteBytes: [
        [
            "0x5028497af0c9a54ea8c6d42a054c0341b9fc6168000100000000000000000004",
            0,
            1
        ]
    ],
    rewardAssets: [
      wstETH, 
      bbrfETH,
      ETH
    ],
    rewardRoute: [
      [
        "0x88d07558470484c03d3bb44c3ecc36cafcf43253000000000000000000000051",
        0,
        1
      ],
      [
        "0x899f737750db562b88c1e412ee1902980d3a4844000200000000000000000081",
        1,
        2
      ],
      [
        "0xde45f101250f2ca1c0f8adfc172576d10c12072d00000000000000000000003f",
        2,
        3
      ],
      [
        "0xdd89c7cd0613c1557b2daac6ae663282900204f100000000000000000000003e",
        3,
        4
      ]
    ],
    secondRewardAssets: [
      "0x0000000000000000000000000000000000000000",
    ],
    secondRewardRoute: [
      [
        bytes0,
        0,
        1
      ],
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
  console.log(rewardToNativeRouteBytes);

  const factory = await ethers.getContractAt(vaultV7Factory.abi, strategyParams.beefyVaultProxy);
  let vault = await factory.callStatic.cloneVault();
  let tx = await factory.cloneVault();
  tx = await tx.wait();
  tx.status === 1
  ? console.log(`Vault ${vault} is deployed with tx: ${tx.transactionHash}`)
  : console.log(`Vault ${vault} deploy failed with tx: ${tx.transactionHash}`);


  let strat = await factory.callStatic.cloneContract(strategyParams.strategyImplementation);
  let stratTx = await factory.cloneContract(strategyParams.composableStrat ? strategyParams.comStrategyImplementation : strategyParams.strategyImplementation);
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
    want,
    [
      strategyParams.isComposable,
      strategyParams.isBeets
    ],
    strategyParams.nativeToWantRouteBytes,
    strategyParams.outputToNativeRouteBytes,
    [
      strategyParams.outputToNativeAssets,
      strategyParams.nativeToWantAssets
    ],
    gauge,
    [vault,
    strategyParams.unirouter,
    strategyParams.keeper,
    strategyParams.strategist,
    strategyParams.beefyFeeRecipient,
    strategyParams.beefyFeeConfig],
  ];

  const comStrategyConstructorArguments = [
    strategyParams.nativeToWantRouteBytes,
    strategyParams.outputToNativeRouteBytes,
    [
      strategyParams.outputToNativeAssets,
      strategyParams.nativeToWantAssets
    ],
    gauge,
    strategyParams.isBeets,
    [vault,
    strategyParams.unirouter,
    strategyParams.keeper,
    strategyParams.strategist,
    strategyParams.beefyFeeRecipient,
    strategyParams.beefyFeeConfig],
  ];

  let abi = strategyParams.composableStrat ? stratComAbi.abi : stratAbi.abi;
  const stratContract = await ethers.getContractAt(abi, strat);
  let args = strategyParams.composableStrat ? comStrategyConstructorArguments : strategyConstructorArguments
  let stratInitTx = await stratContract.initialize(...args);
  stratInitTx = await stratInitTx.wait()
  stratInitTx.status === 1
  ? console.log(`Strat Intilization done with tx: ${stratInitTx.transactionHash}`)
  : console.log(`Strat Intilization failed with tx: ${stratInitTx.transactionHash}`);


  if (strategyParams.extraReward) {
    stratInitTx = await stratContract.addRewardToken(strategyParams.rewardAssets[0], strategyParams.rewardRoute, strategyParams.rewardAssets, bytes0, 100);
    stratInitTx = await stratInitTx.wait()
    stratInitTx.status === 1
    ? console.log(`Reward Added with tx: ${stratInitTx.transactionHash}`)
    : console.log(`Reward Addition failed with tx: ${stratInitTx.transactionHash}`);
  }

  if (strategyParams.secondExtraReward) {
    stratInitTx = await stratContract.addRewardToken(LDO, strategyParams.secondRewardRoute, strategyParams.secondRewardAssets, rewardToNativeRouteBytes, 100);
    stratInitTx = await stratInitTx.wait()
    stratInitTx.status === 1
    ? console.log(`Reward Added with tx: ${stratInitTx.transactionHash}`)
    : console.log(`Reward Addition failed with tx: ${stratInitTx.transactionHash}`);
  }
  // add this info to PR
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });