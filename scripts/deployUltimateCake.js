const hardhat = require("hardhat");

const registerSubsidy = require("../utils/registerSubsidy");
const predictAddresses = require("../utils/predictAddresses");
const { getNetworkRpc } = require("../utils/getNetworkRpc");
const { deployVault } = require("../../utils/deployVault");

const ethers = hardhat.ethers;

const config = {
  want: "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82",
  mooName: "Moo Bunny Cake",
  mooSymbol: "mooBunnyCake",
  delay: 21600,
  keeper: "0x9295E05d5cd1cfA617875Ba1cF984D65830d1a4c",
  strategist: "0xB60d9512CC129f539313b7Bdbd13bBa1Fd2fE3C3",
};

async function main() {
  await hardhat.run("compile");

  const simpleCakeWorker = await deployVault({
    vault: "BeefyVaultV5",
    strategy: "StrategyCakeWorker",
    want: config.want,
    mooName: "Moo Cake Worker",
    mooSymbol: "mooCakeWorker",
    delay: config.delay,
    stratArgs: [config.strategist],
    signer: signer,
    rpc: RPC,
  });

  const bunnyDelegator = await deployVault({
    vault: "BeefyVaultV5",
    strategy: "StrategyBunnyCakeWorker",
    want: config.want,
    mooName: "Moo Cake Worker",
    mooSymbol: "mooCakeWorker",
    delay: config.delay,
    stratArgs: [config.strategist],
    signer: signer,
    rpc: RPC,
  });

  const bunnyCompounder = await deployVault({
    vault: "BeefyVaultV5",
    strategy: "StrategyBunnyCakeWorker",
    want: config.want,
    mooName: "Moo Cake Worker",
    mooSymbol: "mooCakeWorker",
    delay: config.delay,
    stratArgs: [config.strategist],
    signer: signer,
    rpc: RPC,
  });

  const yieldBalancer = await deployVault({
    vault: "BeefyVaultV5",
    strategy: "YieldBalancer",
    want: config.want,
    mooName: "Ultimate Cake",
    mooSymbol: "UltimateCake",
    delay: config.delay,
    stratArgs: [
      config.want,
      [simpleCakeWorker.vault.address, bunnyDelegator.vault.address, bunnyCompounder.vault.address],
      config.delay,
      10,
    ],
    signer: signer,
    rpc: RPC,
  });

  const Vault = await ethers.getContractFactory("BeefyVaultV5");
  const Strategy = await ethers.getContractFactory("StrategyBunnyCake");

  const [deployer] = await ethers.getSigners();
  const rpc = getNetworkRpc(hardhat.network.name);

  console.log("Deploying:", config.mooName);

  // 1. Deploy YieldBalancer

  // 2. Deploy SimpleCake worker

  // 3. Deploy BunnyCake delegator

  // 4. Deploy BunnyCake compounder

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc });

  const vault = await Vault.deploy(
    config.want,
    predictedAddresses.strategy,
    config.mooName,
    config.mooSymbol,
    config.delay
  );
  await vault.deployed();

  const strategy = await Strategy.deploy(predictedAddresses.vault, config.keeper, config.strategist);
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
