const hardhat = require("hardhat");

const { predictAddresses } = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");
const registerSubsidy = require("../utils/registerSubsidy");

const ethers = hardhat.ethers;

const pools = [
  {
    want: "0xc92Dc34665c8a21f98E1E38474580b61b4f3e1b9",
    mooName: "Moo Street MAMZN-UST",
    mooSymbol: "mooStreetMAMZN-UST",
    poolId: 62,
    strategist: "0xd529b1894491a0a26B18939274ae8ede93E81dbA",
  },
  {
    want: "0x852A68181f789AE6d1Da3dF101740a59A071004f",
    mooName: "Moo Street MGOOGL-UST",
    mooSymbol: "mooStreetMGOOGL-UST",
    poolId: 61,
    strategist: "0xd529b1894491a0a26B18939274ae8ede93E81dbA",
  },
  {
    want: "0xF609ade3846981825776068a8eD7746470029D1f",
    mooName: "Moo Street MNFLX-UST",
    mooSymbol: "mooStreetMNFLX-UST",
    poolId: 60,
    strategist: "0xd529b1894491a0a26B18939274ae8ede93E81dbA",
  },
  {
    want: "0xD5664D2d15cdffD597515f1c0D945c6c1D3Bf85B",
    mooName: "Moo Street MTSLA-UST",
    mooSymbol: "mooStreetMTSLA-UST",
    poolId: 59,
    strategist: "0xd529b1894491a0a26B18939274ae8ede93E81dbA",
  },
];

async function main() {
  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory("BeefyVaultV3");
  const Strategy = await ethers.getContractFactory("StrategyCakeMirrorLP");

  const pool = pools[3];

  console.log("Deploying:", pool.mooName);

  const [deployer] = await ethers.getSigners();
  const rpc = getNetworkRpc(hardhat.network.name);

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc });

  const vault = await Vault.deploy(pool.want, predictedAddresses.strategy, pool.mooName, pool.mooSymbol, 86400);
  await vault.deployed();

  const strategy = await Strategy.deploy(pool.want, pool.poolId, predictedAddresses.vault, pool.strategist);
  await strategy.deployed();

  console.log("Vault deployed to:", vault.address);
  console.log("Strategy deployed to:", strategy.address);

  await registerSubsidy(vault.address, strategy.address, deployer);

  console.log("---");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
