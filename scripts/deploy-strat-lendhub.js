const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");

const ethers = hardhat.ethers;

const config = {
    strategyName: "StrategyLendhub",
    mooName: "Moo Lendhub DOT",
    mooSymbol: "mooLendhubDOT",
    delay: 21600,
    iToken: "0x6371531A3493466788179AEECe337d38117fa1ac",
    borrowRate: 68,
    borrowRateMax: 70,
    borrowDepth: 4,
    minLeverage: 1000000000000,
    markets: ["0x6371531A3493466788179AEECe337d38117fa1ac"],
    unirouter: "0xED7d5F38C79115ca12fe6C0041abb22F0A06C300",
    keeper: "0x10aee6B5594942433e7Fc2783598c979B030eF3D",
    strategist:"0x010dA5FF62B6e45f89FA7B2d8CEd5a8b5754eC1b",
    beefyFeeRecipient:"0x183D1aaEf1a86De6f16B2737c30eF94a6d2A9308"
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

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc:"https://http-mainnet.hecochain.com" });

  const vault = await Vault.deploy(predictedAddresses.strategy, config.mooName, config.mooSymbol, config.delay);
  await vault.deployed();

  const strategy = await Strategy.deploy(
    config.iToken,
    config.borrowRate,
    config.borrowRateMax,
    config.borrowDepth,
    config.minLeverage,
    config.markets,
    vault.address,
    config.unirouter,
    config.keeper,
    config.strategist,
    config.beefyFeeRecipient
  );
  await strategy.deployed();

  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);

  await hardhat.run("verify:verify", {
    address: vault.address,
    constructorArguments: [
      strategy.address, config.mooName, config.mooSymbol, config.delay
    ],
  })
  
  await hardhat.run("verify:verify", {
    address: strategy.address,
    constructorArguments: [
      config.iToken,
      config.borrowRate,
      config.borrowRateMax,
      config.borrowDepth,
      config.minLeverage,
      config.markets,
      vault.address,
      config.unirouter,
      config.keeper,
      config.strategist,
      config.beefyFeeRecipient
    ],
  })
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

