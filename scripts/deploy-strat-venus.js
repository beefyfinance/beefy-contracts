const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses").predictAddresses;
const getNetworkRpc = require("../utils/getNetworkRpc");

const ethers = hardhat.ethers;

const config = {
  want: "0x0d8ce2a99bb6e3b7db580ed848240e4a0f9ae153",
  mooName: "Moo Venus FIL",
  mooSymbol: "mooVenusFIL",
  delay: 86400,
  vToken: "0xf91d58b5ae142dacc749f58a49fcbac340cb0343",
  borrowRate: 56,
  borrowDepth: 4,
  minLeverage: 1000000000000,
  markets: ["0xf91d58b5ae142dacc749f58a49fcbac340cb0343"],
};

async function main() {
  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory("BeefyVenusVault");
  const Strategy = await ethers.getContractFactory("StrategyVenus");

  const [deployer] = await ethers.getSigners();
  const rpc = getNetworkRpc(hardhat.network.name);

  console.log("Deploying:", config.mooName);

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc });

  const vault = await Vault.deploy(
    predictedAddresses.strategy,
    config.want,
    config.mooName,
    config.mooSymbol,
    config.delay
  );
  await vault.deployed();

  const strategy = await Strategy.deploy(
    predictedAddresses.vault,
    config.vToken,
    config.borrowRate,
    config.borrowDepth,
    config.minLeverage,
    config.markets
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
