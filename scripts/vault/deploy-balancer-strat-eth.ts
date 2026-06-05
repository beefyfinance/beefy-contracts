import hardhat, { ethers } from "hardhat";
import { addressBook } from "@beefyfinance/blockchain-addressbook";
import vaultV7 from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";
import stratAbi from "../../artifacts/contracts/BIFI/strategies/Balancer/StrategyAuraGyroMainnet.sol/StrategyAuraGyroMainnet.json";
import { getAddress } from "viem";

const {
  platforms: { balancer, beefyfinance },
  tokens: {
    BAL: { address: BAL },
    ETH: { address: ETH },
    cbETH: { address: cbETH },
    wstETH: { address: wstETH },
    AURA: { address: AURA },
    
  },
} = addressBook.ethereum;

const bytes0 = '0x0000000000000000000000000000000000000000000000000000000000000000';

const booster = getAddress("0xA57b8d98dAE62B26Ec3bcC4a365338157060B234");
const want = getAddress("0xf01b0684C98CD7aDA480BFDF6e43876422fa1Fc1");

const vaultParams = {
  mooName: "Moo Aura Gyro wstETH-ETH",
  mooSymbol: "mooAuraGyrowstETH-ETH",
  delay: 21600,
};

const strategyParams = {
  want: want,
  booster: booster,
  pid: 162,
  input: wstETH,
  isComposable: false,
  unirouter: balancer.router,
  strategist: process.env.STRATEGIST_ADDRESS,
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  beefyFeeConfig: beefyfinance.beefyFeeConfig,
  beefyVaultProxy: "0xC551dDCE8e5E657503Cd67A39713c06F2c0d2e97", //beefyfinance.vaultProxy,
  strategyImplementation: "0x2b494952C10632B11fEf3139C38fE2AD939F4243",
  useVaultProxy: true,
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
    wstETH
  ],
  nativeToLp0RouteBytes: [
        [
            "0x93d199263632a4ef4bb438f1feb99e57b4b5f0bd0000000000000000000005c2",
            0,
            1
        ]
    ],
    lp0ToLp1Assets: [
      wstETH,
      ETH
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

  const stratContract = await ethers.getContractAt(stratAbi.abi, strat);
  let stratInitTx = await stratContract.initialize(...strategyConstructorArguments);
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