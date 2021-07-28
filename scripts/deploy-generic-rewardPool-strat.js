const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const { getNetworkRpc } = require("../utils/getNetworkRpc");

const { addressBook } = require("blockchain-addressbook")
const { BNB: { address: BNB }, BIFI: { address: BIFI }, PNG: { address: PNG }, WAVAX: { address: WAVAX} } = addressBook.avax.tokens;
const { pangolin, beefyfinance } = addressBook.avax.platforms;

const ethers = hardhat.ethers;

const want = web3.utils.toChecksumAddress("0x76BC30aCdC88b2aD2e8A5377e59ed88c7f9287f9");
const rewardPool = web3.utils.toChecksumAddress("0x68a90C38bF4f90AC2a870d6FcA5b0A5A218763AD");

const vaultParams = {
  mooName: "Moo Pangolin BNB-PNG",
  mooSymbol: "mooPangolinBNB-PNG",
  delay: 21600,
}

const strategyParams = {
  want: want,
  rewardPool: rewardPool,
  unirouter: pangolin.router,
  strategist: "0x010dA5FF62B6e45f89FA7B2d8CEd5a8b5754eC1b", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToIntermediateRoute: [ PNG, WAVAX ],
  outputToLp0Route: [ PNG, BNB ],
  outputToLp1Route: [ PNG ]
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

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc });

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
