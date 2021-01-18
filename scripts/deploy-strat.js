const hardhat = require("hardhat");

const { predictAddresses } = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");

const ethers = hardhat.ethers;

const config = {
  want: "0x339550404Ca4d831D12B1b2e4768869997390010",
  smartGangster: "0x2a1A101C9213fCf6844685d5886ea4107229b3db",
  mooName: "Mock Name",
  mooSymbol: "mockSymbol",
  delay: 86400,
};

async function main() {
  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory("BeefyVaultV2");
  const Strategy = await ethers.getContractFactory("StrategyHoesVaultV2");

  const [deployer] = await ethers.getSigners();
  const rpc = getNetworkRpc(hardhat.network.name);

  console.log("Deploying:", config.mooName);

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc });

  const vault = await Vault.deploy(
    config.want,
    predictedAddresses.strategy,
    config.mooName,
    config.mooSymbol,
    config.delay
  );
  await vault.deployed();

  const strategy = await Strategy.deploy(config.smartGangster, predictedAddresses.vault);
  await strategy.deployed();

  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
