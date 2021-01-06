const hardhat = require("hardhat");

const predictAddresses = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");

const ethers = hardhat.ethers;

const config = [
  {
    want: "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82",
    mooName: "Mock Balancer",
    mooSymbol: "mockBalancer",
    delay: 86400,
  },
];

async function main() {
  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory("BeefyVaultV3");
  const Strategy = await ethers.getContractFactory("StrategyStaticBalancer");

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

  const strategy = await Strategy.deploy(config.want, predictedAddresses.vault);
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
