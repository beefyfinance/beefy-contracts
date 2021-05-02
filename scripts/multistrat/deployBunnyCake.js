const hardhat = require("hardhat");

const predictAddresses = require("../../utils/predictAddresses");
const getNetworkRpc = require("../../utils/getNetworkRpc");

const ethers = hardhat.ethers;

const config = {
  want: "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82",
  mooName: "Moo Test",
  mooSymbol: "mooTest",
  delay: 21600,
  unirouter: "0x10ED43C718714eb63d5aA57B78B54704E256024E",
  keeper: "0xd529b1894491a0a26B18939274ae8ede93E81dbA",
  strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
  beefyFeeRecipient: "0xEB41298BA4Ea3865c33bDE8f60eC414421050d53",
};

async function main() {
  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory("BeefyVaultV6");
  const Strategy = await ethers.getContractFactory("StrategyBunnyCake");

  const [deployer] = await ethers.getSigners();
  const rpc = getNetworkRpc(hardhat.network.name);

  console.log("Deploying:", config.mooName);

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc });

  const vault = await Vault.deploy(predictedAddresses.strategy, config.mooName, config.mooSymbol, config.delay);
  await vault.deployed();

  const strategy = await Strategy.deploy(
    config.want,
    config.keeper,
    config.strategist,
    config.unirouter,
    config.beefyFeeRecipient,
    predictedAddresses.vault
  );
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
