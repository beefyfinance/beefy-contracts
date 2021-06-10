const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");

const ethers = hardhat.ethers;

const cake = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";
const wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
const busd = "0xe9e7cea3dedca5984780bafc599bd69add087d56";
const usdc = "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d";
const eth = "0x2170Ed0880ac9A755fd29B2688956BD959F933F8";

const config = {
  want: "0xEa26B78255Df2bBC31C1eBf60010D78670185bD0",
  mooName: "Moo CakeV2 ETH-USDC",
  mooSymbol: "mooCakeV2ETH-USDC",
  delay: 21600,
  strategyName: "StrategyCakeRoutableLP",
  poolId: 409,
  unirouter: "0x10ED43C718714eb63d5aA57B78B54704E256024E", // Pancakeswap Router V2
  strategist: "0xEB41298BA4Ea3865c33bDE8f60eC414421050d53", // your address for rewards
  keeper: "0xd529b1894491a0a26B18939274ae8ede93E81dbA",
  beefyFeeRecipient: "0xEB41298BA4Ea3865c33bDE8f60eC414421050d53",
  cakeToLp0Route: [ cake, wbnb, eth ],
  cakeToLp1Route: [ cake, busd, usdc ],
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

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc });

  const vault = await Vault.deploy(predictedAddresses.strategy, config.mooName, config.mooSymbol, config.delay);
  await vault.deployed();

  const strategy = await Strategy.deploy(
    config.want,
    config.poolId,
    vault.address,
    config.unirouter,
    config.keeper,
    config.strategist,
    config.beefyFeeRecipient,
    config.cakeToLp0Route,
    config.cakeToLp1Route,
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
