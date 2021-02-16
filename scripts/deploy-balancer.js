const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");

const ethers = hardhat.ethers;

const config = {
  want: "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82",
  mooName: "Moo Balancer",
  mooSymbol: "mooBalancer",
  delay: 86400,
  workers: ["0x9f3fC432DcEC1d5cB29f373fBe1bFc2AB1597336", "0x0E9497c5be97624f6ad19251655ffc3b78cde5d1"],
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
