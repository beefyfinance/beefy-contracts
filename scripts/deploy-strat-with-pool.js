const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");

const ethers = hardhat.ethers;

const config = {
  want: "0x51a2ffa5B7DE506F9a22549E48B33F6Cf0D9030e",
  mooName: "Moo Pancake UNI-BNB V2",
  mooSymbol: "mooPancakeUNI-BNBV2",
  delay: 21600,
  strategyName: "StrategyCakeLP",
  poolId: 157,
  unirouter: "0x2AD2C5314028897AEcfCF37FD923c079BeEb2C56", // Pancakeswap Router
  strategist: "0xB1f1F1ed9e874cF4c81C6b16eFc2642B4c8Fb8A5", // some address
  keeper: "0xd529b1894491a0a26B18939274ae8ede93E81dbA",
  beefyFeeRecipient: "0xEB41298BA4Ea3865c33bDE8f60eC414421050d53",
};

async function main() {
  if (Object.values(config).some((v) => v === undefined)) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory("BeefyVaultV4");
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
    predictedAddresses.vault,
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
