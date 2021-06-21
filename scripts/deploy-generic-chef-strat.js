const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const predictAddresses = require("../utils/predictAddresses");
const getNetworkRpc = require("../utils/getNetworkRpc");
const { addressBook } = require("blockchain-addressbook");
const { beefyfinance } = addressBook.polygon.platforms;
const {
  BIFI: { address: BIFI },
  USDC: { address: USDC },
  USDT: { address: USDT },
  WMATIC: { address: WMATIC },
  BANANA: { address: BANANA }
} = addressBook.polygon.tokens;

const c = {
  delay: 21600,
  vaultName: "BeefyVaultV6",
  strategyName: "StrategyPolygonMiniChefLP",
  // strategyName: "StrategyRewardPoolPolygonETHLP",
  unirouter: "0xC0788A3aD43d79aa53B09c2EaCc313A787d1d607", // apeswap
  // unirouter: "0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff", // quickswap
  // unirouter: "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506", // sushi
  // unirouter: "0x3a1D87f206D12415f5b0A33E786967680AAb4f6d", // waultswap
  // unirouter: "0x4aAEC1FA8247F85Dc3Df20F4e03FEAFdCB087Ae9", // polyzap
  keeper: beefyfinance.keeper,
  strategist: "0x982F264ce97365864181df65dF4931C593A515ad",
  beefyFeeRecipient: beefyfinance.beefyFeeRecipient
};

const configs = [
  {
    poolId: 0,
    want: "0x034293F21F1cCE5908BC605CE5850dF2b1059aC0",
    chef: "0x54aff400858Dcac39797a81894D9920f16972D1D",
    mooName: "Moo ApeSwap BANANA-MATIC",
    mooSymbol: "mooApeSwapBANANA-MATIC",
    ...c,
    outputToNativeRoute: [BANANA, WMATIC],
    outputToLp0Route: [BANANA, WMATIC],
    outputToLp1Route: []
  },
  {
    mooName: "Moo Curve am3CRV",
    mooSymbol: "mooCurveAm3CRV",
    ...c
  },

  {
    rewardPool: "0x2dF6A6b1B7aA23a842948a81714a2279e603e32f",
    want: "0xA28Ade2f27b9554b01964FDCe97eD643301411d9",
    mooName: "Moo Quick TITAN-ETH",
    mooSymbol: "mooQuickTITAN-ETH",
    ...c
  }
];

async function main() {
  const config = configs[0];
  if (Object.values(config).some((v) => v === undefined)) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const Vault = await ethers.getContractFactory(config.vaultName);
  const Strategy = await ethers.getContractFactory(config.strategyName);

  const [deployer] = await ethers.getSigners();
  const rpc = getNetworkRpc(hardhat.network.name);

  console.log("Deploying:", config.mooName);

  const predictedAddresses = await predictAddresses({ creator: deployer.address, rpc });

  const vault = await Vault.deploy(
    predictedAddresses.strategy,
    config.mooName,
    config.mooSymbol,
    config.delay,
    // { gasPrice: 100000000000 }
  );
  await vault.deployed();

  const strategy = await Strategy.deploy(
    config.want,
    config.poolId,
    config.chef,
    vault.address,
    config.unirouter,
    config.keeper,
    config.strategist,
    config.beefyFeeRecipient,
    config.outputToNativeRoute,
    config.outputToLp0Route,
    config.outputToLp1Route,
    // { gasPrice: 100000000000 }
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
