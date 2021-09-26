const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const { getNetworkRpc } = require("../utils/getNetworkRpc");
const { addressBook } = require("blockchain-addressbook")
const { MIM: { address: MIM }, SUSHI: { address: SUSHI }, WETH: { address: WETH}, SPELL: {address: SPELL } } = addressBook.arbitrum.tokens;
const { sushi, beefyfinance } = addressBook.arbitrum.platforms;

const ethers = hardhat.ethers;

const want = web3.utils.toChecksumAddress("0xb6DD51D5425861C808Fd60827Ab6CFBfFE604959");

const vaultParams = {
  mooName: "Moo Sushi MIM-WETH",
  mooSymbol: "mooSushiMIM-WETH",
  delay: 21600,
}

const strategyParams = {
  want: want,
  poolId: 9,
  chef: sushi.minichef,
  unirouter: sushi.router,
  strategist: "0x010dA5FF62B6e45f89FA7B2d8CEd5a8b5754eC1b", // some address
  keeper: beefyfinance.keeper,
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  outputToNativeRoute: [ SUSHI, WETH ],
  rewardToOutputRoute: [ SPELL, WETH, SUSHI ],
  outputToLp0Route: [ SUSHI, WETH ],
  outputToLp1Route: [ SUSHI, WETH, MIM ]
};

const contractNames = {
  vault: "BeefyVaultV6",
  strategy: "StrategyArbSushiMimLP"
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
//  const rpc = getNetworkRpc(hardhat.network.name);

  console.log("Deploying:", vaultParams.mooName);

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc: "https://arb1.arbitrum.io/rpc" });

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
    strategyParams.rewardToOutputRoute,
    strategyParams.outputToLp0Route,
    strategyParams.outputToLp1Route
  );
  await strategy.deployed();

  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);
  console.log("Want:", strategyParams.want);

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