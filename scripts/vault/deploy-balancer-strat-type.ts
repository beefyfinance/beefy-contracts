import hardhat, { ethers } from "hardhat";
import { addressBook } from "@beefyfinance/blockchain-addressbook";
import vaultV7 from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";
import stratAbi from "../../artifacts/contracts/BIFI/strategies/Balancer/StrategyBalancerMultiRewardGaugeUniV3.sol/StrategyBalancerMultiRewardGaugeUniV3.json";
import stratComAbi from "../../artifacts/contracts/BIFI/strategies/Balancer/StrategyBalancerComposableMultiRewardGaugeUniV3.sol/StrategyBalancerComposableMultiRewardGaugeUniV3.json";

const {
  platforms: { beethovenX, beefyfinance },
  tokens: {
    BAL: { address: BAL },
    'wUSD+': { address: wUSDplus },
    rETH: { address: rETH },
    OP: { address: OP },
    wstETH: {address: wstETH },
    ETH: {address: ETH },
    USDC: {address: USDC}
  },
} = addressBook.optimism;

const bbrfBAL = "0xd0d334B6CfD77AcC94bAB28C7783982387856449";
const bbrfETH = "0xdd89c7cd0613c1557b2daac6ae663282900204f1";
const bbrfOP = "0xA4e597c1bD01859B393b124ce18427Aa4426A871";
const bbUSDplus = "0x88D07558470484c03d3bb44c3ECc36CAfCF43253";

const gauge = getAddress("0x6341B7472152D7b7F9af3158C6A42349a2cA6c72");
const want = getAddress("0x7B50775383d3D6f0215A8F290f2C9e2eEBBEceb2");

const vaultParams = {
  mooName: "Moo Beets Shanghai Shakedown",
  mooSymbol: "mooBeetsShanghaiShakedown",
  delay: 21600,
};

const bytes0 = '0x0000000000000000000000000000000000000000000000000000000000000000';

const strategyParams = {
  input: wstETH,
  isComposable: false,
  unirouter: beethovenX.router,
  strategist: process.env.STRATEGIST_ADDRESS,
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  beefyFeeConfig: beefyfinance.beefyFeeConfig,
  isBeets: true,
  beefyVaultProxy: "0xA6D3769faC465FC0415e7E9F16dcdC96B83C240B",  //beefyfinance.vaultProxy,
  composableStrat: false,
  strategyImplementation: "0x5064c531Af73BeEe8e7B3835dE289965B34CC189",
  comStrategyImplementation: "0x617B09c47c3918207fA154b7b789a8E5CDC1680A",
  useVaultProxy: true,
  extraReward: false, 
  secondExtraReward: true,
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
  nativeToWantAssets: [
    ETH,
    wstETH,
  ],
  nativeToWantRouteBytes: [
        [
            "0x7b50775383d3d6f0215a8f290f2c9e2eebbeceb200020000000000000000008b",
            0,
            1
        ]
    ],
    rewardAssets: [
      wUSDplus,
      USDC,
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
      OP,
      ETH
    ],
    secondRewardRoute: [
      [
        "0x39965c9dab5448482cf7e002f583c812ceb53046000100000000000000000003",
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
    stratInitTx = await stratContract.addRewardToken(strategyParams.secondRewardAssets[0], strategyParams.secondRewardRoute, strategyParams.secondRewardAssets, bytes0, 100);
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