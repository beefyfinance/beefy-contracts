const hardhat = require("hardhat");

const registerSubsidy = require("../../utils/registerSubsidy");
const predictAddresses = require("../../utils/predictAddresses");
const { getNetworkRpc } = require("../../utils/getNetworkRpc");

const ethers = hardhat.ethers;

const config = {
  want: "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82",
  mooName: "Moo Balancer",
  mooSymbol: "mooBalancer",
  delay: 86400,
  workers: ["0x2954086Fc40b1a4c39e298297550e68C56d0339f", "0xa3935D4ff028Ed3fb9f6b2ED503d05F25670328A"],
  workersMax: 3,
};

async function main() {
  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory("BeefyVaultV4");
  const Strategy = await ethers.getContractFactory("YieldBalancer");

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

  const strategy = await Strategy.deploy(
    config.want,
    config.workers,
    config.delay,
    config.workersMax,
    predictedAddresses.vault
  );
  await strategy.deployed();

  console.log("Vault deployed to:", vault.address);
  console.log("Balancer deployed to:", strategy.address);

  //   await registerSubsidy(vault.address, deployer);
  //   await registerSubsidy(strategy.address, deployer);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
