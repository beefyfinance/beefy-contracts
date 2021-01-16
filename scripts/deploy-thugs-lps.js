const hardhat = require("hardhat");

const predictAddresses = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");
const registerSubsidy = require("../utils/registerSubsidy");

const ethers = hardhat.ethers;

const pools = [
  {
    want: "0xf7f21A56B19546A77EABABf23d8dca726CaF7577",
    unirouter: "0x3bc677674df90A9e5D741f28f6CA303357D0E4Ec",
    mooName: "Moo Street TWT-BNB",
    mooSymbol: "mooStreetTWT-BNB",
    poolId: 22,
  },
  {
    want: "0xf08865069864A5a62EB4DD4b9dcB66834822a198",
    unirouter: "0x3bc677674df90A9e5D741f28f6CA303357D0E4Ec",
    mooName: "Moo Street SXP-BNB",
    mooSymbol: "mooStreetSXP-BNB",
    poolId: 23,
  },
];

async function main() {
  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory("BeefyVaultV2");
  const Strategy = await ethers.getContractFactory("StrategyThugsLP");

  for (pool of pools) {
    console.log("Deploying:", pool.mooName);

    const [deployer] = await ethers.getSigners();
    const rpc = getNetworkRpc(hardhat.network.name);

    const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc });

    const vault = await Vault.deploy(pool.want, predictedAddresses.strategy, pool.mooName, pool.mooSymbol, 86400);
    await vault.deployed();

    const strategy = await Strategy.deploy(pool.want, pool.poolId, predictedAddresses.vault, pool.unirouter);
    await strategy.deployed();

    console.log(JSON.stringify(predictedAddresses));
    console.log("Vault deployed to:", vault.address);
    console.log("Strategy deployed to:", strategy.address);

    await registerSubsidy(vault.address, strategy.address, deployer);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
