const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses").predictAddresses;
const getNetworkRpc = require("../utils/getNetworkRpc");

const ethers = hardhat.ethers;

const config = {
  want: "0x6F695Bd5FFD25149176629f8491A5099426Ce7a7",
  mooName: "Moo Alpaca sALPACA",
  mooSymbol: "mooAlpacasALPACA",
  delay: 21600,
  strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
};

async function main() {
  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory("BeefyVaultV5");
  const Strategy = await ethers.getContractFactory("StrategyStronkAlpaca");

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

  const strategy = await Strategy.deploy(predictedAddresses.vault, config.strategist);
  await strategy.deployed();

  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);

  // await registerSubsidy(vault.address, deployer);
  // await registerSubsidy(strategy.address, deployer);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
