import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import vaultV7 from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";
import stratAbi from "../../artifacts/contracts/BIFI/strategies/Velodrome/StrategyVelodrome.sol/StrategyVelodrome.json";
import { setOracle } from "../manage/oracle/oracle";
import { setSwapper } from "../manage/swapper/swapper";

const {
  platforms: { beefyfinance },
  tokens: {
    WETH: {address: WETH},
    AERO: {address: AERO},
  },
} = addressBook.base;

const want = web3.utils.toChecksumAddress("0x7f670f78B17dEC44d5Ef68a48740b6f8849cc2e6");

const vaultParams = {
  mooName: "Moo Aero WETH-AERO",
  mooSymbol: "mooAeroWETH-AERO",
  delay: 21600,
};

const strategyParams = {
  want: want,
  native: WETH,
  rewards: [AERO],
  core: '', //beefyfinance.core,
  unirouter: "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43",
  strategist: process.env.STRATEGIST_ADDRESS, // some address
  beefyVaultProxy: beefyfinance.vaultFactory,
  strategyImplementation: "0x7Fc8743Dd54c3dd7344cbF06e3AaDE63DADaE1d3",
};

const oracleParams = [
  {
    token: AERO,
    oracleType: 'chainlink',
    feed: '0x4EC5970fC728C5f65ba413992CD5fF6FD70fcfF0',
  },
  {
    token: WETH,
    oracleType: 'chainlink',
    feed: '0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70',
  }
];

const swapperParams = [
  {
    from: AERO,
    to: WETH,
    steps: [
      {
        stepType: 'solidly',
        router: strategyParams.unirouter,
        path: [AERO, WETH],
        stable: [false],
        fees: [],
        poolId: [],
      }
    ]
  },
  {
    from: WETH,
    to: AERO,
    steps: [
      {
        stepType: 'solidly',
        router: strategyParams.unirouter,
        path: [WETH, AERO],
        stable: [false],
        fees: [],
        poolId: [],
      }
    ]
  },
];

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
  ? console.log(`Vault Initilization done with tx: ${vaultInitTx.transactionHash}`)
  : console.log(`Vault Initilization failed with tx: ${vaultInitTx.transactionHash}`);

  vaultInitTx = await vaultContract.transferOwnership(beefyfinance.vaultOwner);
  vaultInitTx = await vaultInitTx.wait()
  vaultInitTx.status === 1
  ? console.log(`Vault OwnershipTransfered done with tx: ${vaultInitTx.transactionHash}`)
  : console.log(`Vault Initilization failed with tx: ${vaultInitTx.transactionHash}`);

  const strategyConstructorArguments = [
    strategyParams.unirouter,
    [
      strategyParams.want,
      vault,
      strategyParams.core,
      strategyParams.strategist,
      strategyParams.rewards,
    ]
  ];

  let abi = stratAbi.abi;
  const stratContract = await ethers.getContractAt(abi, strat);
  let args = strategyConstructorArguments;
  let stratInitTx = await stratContract.initialize(...args);
  stratInitTx = await stratInitTx.wait()
  stratInitTx.status === 1
  ? console.log(`Strat Initilization done with tx: ${stratInitTx.transactionHash}`)
  : console.log(`Strat Initilization failed with tx: ${stratInitTx.transactionHash}`);

  await Promise.all([setOracle(strat, oracleParams)]);
  await Promise.all([setSwapper(strat, swapperParams)]);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });