const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const { getNetworkRpc } = require("../utils/getNetworkRpc");
const { addressBook } = require("blockchain-addressbook")
const { SCREAM: { address: SCREAM }, USDC: { address: USDC }, WFTM: { address: WFTM } } = addressBook.fantom.tokens;
const { spookyswap, beefyfinance } = addressBook.fantom.platforms;

const iToken = web3.utils.toChecksumAddress("0xE45Ac34E528907d0A0239ab5Db507688070B20bf");

const ethers = hardhat.ethers;

const config = {
    strategyName: "StrategyScream",
    mooName: "Moo Scream USDC",
    mooSymbol: "mooScreamUSDC",
    delay: 21600,
    borrowRate: 72,
    borrowRateMax: 75,
    borrowDepth: 4,
    minLeverage: 1000,
    outputToNativeRoute: [SCREAM, WFTM],
    outputToWantRoute: [SCREAM, WFTM, USDC],
    markets: [iToken];
    comptroller: "0x260E596DAbE3AFc463e75B6CC05d8c46aCAcFB09",
    unirouter: spookyswap.router,
    keeper: beefyfinance.keeper,
    strategist:"0x010dA5FF62B6e45f89FA7B2d8CEd5a8b5754eC1b",
    beefyFeeRecipient:beefyfinance.beefyFeeRecipient
  };

async function main() {
  if (Object.values(config).some((v) => v === undefined)) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory("BeefyVaultV6");
  const Strategy = await ethers.getContractFactory(config.strategyName);

  const [deployer] = await ethers.getSigners();
  const rpc = getNetworkRpc(hardhat.network.name);

  console.log("Deploying:", config.mooName);

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc: "https://rpc.ftm.tools" });

  const vault = await Vault.deploy(predictedAddresses.strategy, config.mooName, config.mooSymbol, config.delay);
  await vault.deployed();

  const strategy = await Strategy.deploy(
    config.borrowRate,
    config.borrowRateMax,
    config.borrowDepth,
    config.minLeverage,
    config.outputToNativeRoute,
    config.outputToWantRoute,
    config.markets,
    config.comptroller,
    vault.address,
    config.unirouter,
    config.keeper,
    config.strategist,
    config.beefyFeeRecipient
  );
  await strategy.deployed();

  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

