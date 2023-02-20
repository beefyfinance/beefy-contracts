import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import vaultV7 from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7.sol/BeefyVaultV7.json";
import vaultV7Factory from "../../artifacts/contracts/BIFI/vaults/BeefyVaultV7Factory.sol/BeefyVaultV7Factory.json";
import stratAbi from "../../artifacts/contracts/BIFI/strategies/Kyber/StrategyKyberLP.sol/StrategyKyberLP.json";

const {
  platforms: { beefyfinance },
  tokens: {
    WETHe: {address: ETH},
    AVAX: { address: AVAX},
    MAI: { address: MAI},
    USDC: { address: USDC },
  },
} = addressBook.avax;

const KNC = '0x39fC9e94Caeacb435842FADeDeCB783589F50f5f'
const chef = '0xF2D574807624bdAd750436AfA940563c5fa34726'

const bytes0 = '0x0000000000000000000000000000000000000000000000000000000000000000';
//const rewardPath = ethers.utils.solidityPack(["address", "uint24", "address"], [OP, 40, ETH]);

const want = web3.utils.toChecksumAddress("0xC2995a065106b5c5c738B2320387460eBd12c12D");

const vaultParams = {
  mooName: "Moo Kyber Avax MAI-USDC",
  mooSymbol: "mooKyberAvaxMAI-USDC",
  delay: 21600,
};

const strategyParams = {
  want: want,
  chef: chef,
  quoter: "0x0D125c15D54cA1F8a813C74A81aEe34ebB508C1f",
  pid: 0,
  paths: [
    ethers.utils.solidityPack(["address", "uint24", "address", "uint24", "address"], [KNC, 300, ETH, 40, AVAX]),
    ethers.utils.solidityPack(["address", "uint24", "address", "uint24", "address"], [AVAX, 1000, USDC, 10, MAI]),
    ethers.utils.solidityPack(["address", "uint24", "address"], [AVAX, 1000, USDC])
  ],
  unirouter: "0x5649B4DD00780e99Bab7Abb4A3d581Ea1aEB23D0",
  elasticRouter: "0xC1e7dFE73E1598E3910EF4C7845B68A9Ab6F4c83",//curve.router,
  strategist: "0xb2e4A61D99cA58fB8aaC58Bb2F8A59d63f552fC0", //process.env.STRATEGIST_ADDRESS,
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  beefyFeeConfig: beefyfinance.beefyFeeConfig,
  beefyVaultProxy: "0x0e264249af87f0c1E10EDB237B2e5E9809C77C70", //beefyfinance.vaultProxy,
  strategyImplementation: "0xDF85F186896f47691e6141f2f66E101D2E177C97",
  useVaultProxy: true,
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
    strategyParams.chef,
    strategyParams.elasticRouter,
    strategyParams.quoter,
    strategyParams.pid,
    strategyParams.paths,
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
/*
  stratInitTx = await stratContract.addRewardToken(OP, [[ethers.constants.AddressZero], [ethers.constants.AddressZero], rewardPath, true, 100]);
  stratInitTx = await stratInitTx.wait()
  stratInitTx.status === 1
  ? console.log(`Reward Added done with tx: ${stratInitTx.transactionHash}`)
  : console.log(`Reward Added failed with tx: ${stratInitTx.transactionHash}`);
  // add this info to PR
*/

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });