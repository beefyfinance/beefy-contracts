const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses").predictAddresses;
const getNetworkRpc = require("../utils/getNetworkRpc");

const ethers = hardhat.ethers;

const config = {
  want: "0x8E04b3972b5C25766c681dFD30a8A1cBf6dcc8c1",
  mooName: "Moo CakeV2 RFOX-BNB",
  mooSymbol: "mooCakeV2RFOX-BNB",
  delay: 21600,
  strategyName: "StrategyCakeLP",
  poolId: 385,
  unirouter: "0x10ED43C718714eb63d5aA57B78B54704E256024E", // Pancakeswap Router V2
  strategist: "0xEB41298BA4Ea3865c33bDE8f60eC414421050d53", // your address for rewards
  keeper: "0xd529b1894491a0a26B18939274ae8ede93E81dbA",
  beefyFeeRecipient: "0xEB41298BA4Ea3865c33bDE8f60eC414421050d53",
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
