const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const { getNetworkRpc } = require("../utils/getNetworkRpc");
const { addressBook } = require("blockchain-addressbook")
const { YFI: { address: YFI }, ETH: { address: ETH }, WFTM: { address: WFTM }, BOO: { address: BOO} } = addressBook.fantom.tokens;
const { spookyswap, beefyfinance } = addressBook.fantom.platforms;

const ethers = hardhat.ethers;

const want = web3.utils.toChecksumAddress("0x0845c0bfe75691b1e21b24351aac581a7fb6b7df");

const vaultParams = {
  mooName: "Moo Boo YFI-ETH",
  mooSymbol: "mooBooYFI-ETH",
  delay: 21600,
}

const strategyParams = {
  want: want,
  poolId: 26,
  chef: spookyswap.masterchef,
  unirouter: spookyswap.router,
  strategist: "0x010dA5FF62B6e45f89FA7B2d8CEd5a8b5754eC1b", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToNativeRoute: [ BOO, WFTM ],
  outputToLp0Route: [ BOO, ETH, YFI ],
  outputToLp1Route: [ BOO, ETH ]
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyCommonChefLP"
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
    strategyParams.poolId,
    strategyParams.chef,
    vault.address,
    strategyParams.unirouter,
    strategyParams.keeper,
    strategyParams.strategist,
    strategyParams.beefyFeeRecipient,
    strategyParams.outputToNativeRoute,
    strategyParams.outputToLp0Route,
    strategyParams.outputToLp1Route
  );
  await strategy.deployed();

  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);

  if (hardhat.network.name === "bsc") {
    await registerSubsidy(vault.address, deployer);
    await registerSubsidy(strategy.address, deployer);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
