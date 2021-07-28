const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const { getNetworkRpc } = require("../utils/getNetworkRpc");

const { addressBook } = require("blockchain-addressbook")
const { YAMP: { address: YAMP }, USDC: { address: USDC }, QUICK: { address: QUICK }, WMATIC: { address: WMATIC} } = addressBook.polygon.tokens;
const { quickswap, beefyfinance } = addressBook.polygon.platforms;

const ethers = hardhat.ethers;

const want = web3.utils.toChecksumAddress("0x87d68f797623590E45982AD0f21228557207FdDa");
const rewardPool = web3.utils.toChecksumAddress("0x1DdF6be5B3c6fe04e5161701e2753b28bBF85dc2");

const vaultParams = {
  mooName: "Moo Quick YAMP-USDC",
  mooSymbol: "mooQuickYAMP-USDC",
  delay: 21600,
}

const strategyParams = {
  want: want,
  rewardPool: rewardPool,
  unirouter: quickswap.router,
  strategist: "0x010dA5FF62B6e45f89FA7B2d8CEd5a8b5754eC1b", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToIntermediateRoute: [ QUICK, WMATIC ],
  outputToLp0Route: [ QUICK, USDC ],
  outputToLp1Route: [ QUICK, USDC, YAMP ]
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyCommonRewardPoolLP"
}

async function main() {
 if (Object.values(vaultParams).some((v) => v === undefined) || Object.values(strategyParams).some((v) => v === undefined) || Object.values(contractNames).some((v) => v === undefined)) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory(contractNames.vault);
  const Strategy = await ethers.getContractFactory(contractNames.strategy);

  const [deployer] = await ethers.getSigners();
  const rpc = getNetworkRpc(hardhat.network.name);

  console.log("Deploying:", vaultParams.mooName);

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc: "https://rpc-mainnet.maticvigil.com/v1/de4204cef56aa2763bc505469cd11605e367e114" });

  const vault = await Vault.deploy(predictedAddresses.strategy, vaultParams.mooName, vaultParams.mooSymbol, vaultParams.delay);
  await vault.deployed();

  const strategy = await Strategy.deploy(
    strategyParams.want,
    strategyParams.rewardPool,
    vault.address,
    strategyParams.unirouter,
    strategyParams.keeper,
    strategyParams.strategist,
    strategyParams.beefyFeeRecipient,
    strategyParams.outputToIntermediateRoute,
    strategyParams.outputToLp0Route,
    strategyParams.outputToLp1Route
  );
  await strategy.deployed();

  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);
  console.log("Staking Token:", strategyParams.want);

  if (hardhat.network.name === "bsc") {
    await registerSubsidy(vault.address, deployer);
    await registerSubsidy(strategy.address, deployer);
  }
/* 
  await hardhat.run("verify:verify", {
    address: vault.address,
    constructorArguments: [
      strategy.address, vaultParams.mooName, vaultParams.mooSymbol, vaultParams.delay
    ],
  })
 
  await hardhat.run("verify:verify", {
    address: "0x6ef302f46543d1045F3c93D2eE77AcD58d3854C4",
    constructorArguments: [
      strategyParams.want,
      strategyParams.rewardPool,
      "0xB198A916123394f2d9c31D4645468566e87080d5",
      strategyParams.unirouter,
      strategyParams.keeper,
      strategyParams.strategist,
      strategyParams.beefyFeeRecipient,
      strategyParams.outputToIntermediateRoute,
      strategyParams.outputToLp0Route,
      strategyParams.outputToLp1Route
    ],
   
  })
 */
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
