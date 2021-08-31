const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");
const { addressBook } = require("blockchain-addressbook")
const { pancake, beefyfinance } = addressBook[hardhat.network.name].platforms;

const ethers = hardhat.ethers;
const rpc = getNetworkRpc(hardhat.network.name);

async function main() {
  const deployer = await ethers.getSigner();

  const config = {
    want: "0x547A355E70cd1F8CAF531B950905aF751dBEF5E6",
    mooName: "Moo CakeV2 WEX-WBNB",
    mooSymbol: "mooCakeV2WEX-WBNB",
    delay: 21600,
    strategyName: "StrategyCakeWbnbLP",
    poolId: 418,
    unirouter: pancake.router, // Pancakeswap Router V2
    strategist: deployer.address, // your address for rewards
    keeper: beefyfinance.keeper,
    beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
  };
  console.log(config)

  if (Object.values(config).some((v) => v === undefined)) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory("BeefyVaultV6");
  const Strategy = await ethers.getContractFactory(config.strategyName);

  console.log("Deploying:", config.mooName);

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc });

  const vault = await Vault.deploy(predictedAddresses.strategy, config.mooName, config.mooSymbol, config.delay);
  await vault.deployed();

  const strategy = await Strategy.deploy(
    config.want,
    config.poolId,
    vault.address,
    config.unirouter,
    config.keeper,
    config.strategist,
    config.beefyFeeRecipient
  );
  await strategy.deployed();

  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);

  await registerSubsidy(vault.address, deployer);
  await registerSubsidy(strategy.address, deployer);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
