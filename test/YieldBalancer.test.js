const { expect } = require("chai");

const { predictAddresses } = require("../utils/predictAddresses");
const { deployVault } = require("../utils/deployVault");

const TIMEOUT = 10 * 60 * 1000;
const RPC = "http://127.0.0.1:8545";

const CAKE = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";
const HELMET_SMARTCHEF = "0x9F23658D5f4CEd69282395089B0f8E4dB85C6e79";
const DITO_SMARTCHEF = "0x624ef5C2C6080Af188AF96ee5B3160Bb28bb3E02";

describe("YieldBalancer", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();

    const workerA = await deployVault({
      vault: "BeefyVaultV3",
      strategy: "StrategyCake",
      want: CAKE,
      mooName: "Worker Simple",
      mooSymbol: "workerSimple",
      delay: 60,
      signer: signer,
      rpc: RPC,
    });

    const workerB = await deployVault({
      vault: "BeefyVaultV3",
      strategy: "StrategySyrup",
      want: CAKE,
      mooName: "Worker Syrup A",
      mooSymbol: "workerSyrupA",
      delay: 60,
      stratArgs: [HELMET_SMARTCHEF],
      signer: signer,
      rpc: RPC,
    });

    const workerC = await deployVault({
      vault: "BeefyVaultV3",
      strategy: "StrategySyrup",
      want: CAKE,
      mooName: "Worker Syrup B",
      mooSymbol: "workerSyrupB",
      delay: 60,
      stratArgs: [DITO_SMARTCHEF],
      signer: signer,
      rpc: RPC,
    });

    const balancer = await deployVault({
      vault: "BeefyVaultV3",
      strategy: "YieldBalancer",
      want: CAKE,
      mooName: "Worker Syrup B",
      mooSymbol: "workerSyrupB",
      delay: 60,
      stratArgs: [HELMET_SMARTCHEF],
      signer: signer,
      rpc: RPC,
    });
  };

  const deployWorker = async (config, signer) => {
    const predictedAddresses = await predictAddresses({ creator: signer.address, rpc: "http://127.0.0.1:8545" });

    console.log(JSON.stringify(predictedAddresses));

    const Vault = await ethers.getContractFactory(config.vault);
    const vault = await Vault.deploy(
      config.want,
      predictedAddresses.strategy,
      config.mooName,
      config.mooSymbol,
      config.delay
    );
    await vault.deployed();

    const Strategy = await ethers.getContractFactory(config.strategy);
    const strategy = await Strategy.deploy(predictedAddresses.vault);
    await strategy.deployed();

    const _vault = await strategy.vault();
    const _strategy = await vault.strategy();

    console.log(vault.address, _vault);
    console.log(strategy.address, _strategy);

    return { vault, strategy };
  };

  it("testing", async () => {
    const result = await setup();
  });
});
