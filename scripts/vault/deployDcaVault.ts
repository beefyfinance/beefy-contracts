import hardhat, { ethers, web3 } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { predictAddresses } from "../../utils/predictAddresses";
import { verifyContract } from "../../utils/verifyContract";

const {
    platforms: { quickswap, beefyfinance },
    tokens: {
      stMATIC: { address: stMATIC },
      MATIC: { address: MATIC },
      ETH: { address: ETH },
    },
  } = addressBook.polygon;

const shouldVerifyOnEtherscan = false;

const want = web3.utils.toChecksumAddress("0x65752C54D9102BDFD69d351E1838A1Be83C924C6");
const mooVault = web3.utils.toChecksumAddress("0x8829ADf1a9a7facE44c8FAb3Bc454f93F330E492");

const vaultParams = {
  mooName: "Beefy WETH DCA Quick stMATIC-MATIC",
  mooSymbol: "b_WETH_DCA_QuickstMATIC-MATIC",
  want: want,
  reward: ETH,
  delay: 0,
};

const strategyParams = {
  want: want,
  poolId: 0,
  mooVault: mooVault,
  reward: ETH,
  unirouter: quickswap.router,
  keeper: beefyfinance.keeper,
  lp0ToRewardRoute: [MATIC, ETH],
  lp1ToRewardRoute: [stMATIC, MATIC, ETH],
};

const contractNames = {
  vault: "BeefyDCAVaultBase",
  strategy: "BeefyDCAStrategyUnirouter",
};

async function main() {
  if (
    Object.values(vaultParams).some(v => v === undefined) ||
    Object.values(strategyParams).some(v => v === undefined) ||
    Object.values(contractNames).some(v => v === undefined)
  ) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory(contractNames.vault);
  const Strategy = await ethers.getContractFactory(contractNames.strategy);

  const [deployer] = await ethers.getSigners();

  console.log("Deploying:", vaultParams.mooName);

  const predictedAddresses = await predictAddresses({ creator: deployer.address });

  const vaultConstructorArguments = [
    vaultParams.mooName,
    vaultParams.mooSymbol,
    vaultParams.want,
    predictedAddresses.strategy,
    vaultParams.reward,
    vaultParams.delay,
  ];
  const vault = await Vault.deploy(...vaultConstructorArguments);
  await vault.deployed();

  const strategyConstructorArguments = [
    strategyParams.mooVault,
    vault.address,
    strategyParams.keeper,
    strategyParams.unirouter,
    strategyParams.lp0ToRewardRoute,
    strategyParams.lp1ToRewardRoute
  ];
  const strategy = await Strategy.deploy(...strategyConstructorArguments);
  await strategy.deployed();

  // add this info to PR
  console.log();
  console.log("Vault:", vault.address);
  console.log("Strategy:", strategy.address);
  console.log("Want:", vaultParams.want);
  console.log("Reward:", vaultParams.reward);

  console.log();
  console.log("Running post deployment");

  const verifyContractsPromises: Promise<any>[] = [];
  if (shouldVerifyOnEtherscan) {
    // skip await as this is a long running operation, and you can do other stuff to prepare vault while this finishes
    verifyContractsPromises.push(
      verifyContract(vault.address, vaultConstructorArguments),
      verifyContract(strategy.address, strategyConstructorArguments)
    );
  }
 
  //console.log(`Transfering Vault Owner to ${beefyfinance.vaultOwner}`)
  //await vault.transferOwnership(beefyfinance.vaultOwner);
  //console.log();

  await Promise.all(verifyContractsPromises);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });