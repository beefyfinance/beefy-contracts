const { expect } = require("chai");

const predictContractAddress = require("../utils/predictAddresses");

const TIMEOUT = 10 * 60 * 1000;

const CAKE = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";

describe("YieldBalancer", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();

    const predictedAddresses = await predictContractAddress({ creator: signer.address, rpc: "http://127.0.0.1:8545" });
    const workerA = await deployWorker(
      {
        vault: "BeefyVaultV3",
        strategy: "StrategyCake",
        want: CAKE,
        mooName: "Worker A",
        mooSymbol: "workerA",
        delay: 60,
      },
      signer
    );
    const workerB = await deployWorker(
      {
        vault: "BeefyVaultV3",
        strategy: "StrategyCake",
        want: CAKE,
        mooName: "Worker B",
        mooSymbol: "workerB",
        delay: 60,
      },
      signer
    );
    const workerC = await deployWorker(
      {
        vault: "BeefyVaultV3",
        strategy: "StrategyCake",
        want: CAKE,
        mooName: "Worker B",
        mooSymbol: "workerB",
        delay: 60,
      },
      signer
    );
    // Worker B
    // Worker C
    // Parent Vault
    // Balancer
  };

  const deployWorker = async (config, signer) => {
    const predictedAddresses = await predictContractAddress({ creator: signer.address, rpc: "http://127.0.0.1:8545" });

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
