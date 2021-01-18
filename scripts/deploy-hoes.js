const hardhat = require("hardhat");

const { predictAddresses } = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");
const registerSubsidy = require("../utils/registerSubsidy");

const ethers = hardhat.ethers;

const pools = [
  {
    want: "0x339550404Ca4d831D12B1b2e4768869997390010",
    mooName: "Moo Drugs BTRI",
    mooSymbol: "mooDrugsBTRI",
    smartGangster: "0xb95F3f5F62F98308A57F84b548c306B852AEF879",
  },
];

async function main() {
  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory("BeefyVaultV3");
  const Strategy = await ethers.getContractFactory("StrategyHoesBurnOnTransfer");

  for (const pool of pools) {
    console.log("---");
    console.log(`Deploying ${pool.mooName}`);

    const [deployer] = await ethers.getSigners();
    const rpc = getNetworkRpc(hardhat.network.name);
    const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc });

    const vault = await Vault.deploy(pool.want, predictedAddresses.strategy, pool.mooName, pool.mooSymbol, 86400);
    await vault.deployed();
    console.log("Vault deployed to:", vault.address);

    const strategy = await Strategy.deploy(pool.smartGangster, predictedAddresses.vault);
    await strategy.deployed();
    console.log("Strategy deployed to:", strategy.address);

    await registerSubsidy(vault.address, strategy.address, deployer);
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
