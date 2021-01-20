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

    const workers = {
      simple: await deployVault({
        vault: "BeefyVaultV3",
        strategy: "StrategyCake",
        want: CAKE,
        mooName: "Worker Simple",
        mooSymbol: "workerSimple",
        delay: 60,
        stratArgs: [],
        signer: signer,
        rpc: RPC,
      }),
      syrupA: await deployVault({
        vault: "BeefyVaultV3",
        strategy: "StrategySyrup",
        want: CAKE,
        mooName: "Worker Syrup A",
        mooSymbol: "workerSyrupA",
        delay: 60,
        stratArgs: [HELMET_SMARTCHEF],
        signer: signer,
        rpc: RPC,
      }),
      syrupB: await deployVault({
        vault: "BeefyVaultV3",
        strategy: "StrategySyrup",
        want: CAKE,
        mooName: "Worker Syrup B",
        mooSymbol: "workerSyrupB",
        delay: 60,
        stratArgs: [DITO_SMARTCHEF],
        signer: signer,
        rpc: RPC,
      }),
    };

    const balancer = await deployVault({
      vault: "BeefyVaultV3",
      strategy: "YieldBalancer",
      want: CAKE,
      mooName: "Yield Balancer",
      mooSymbol: "mooBalancer",
      delay: 60,
      stratArgs: [CAKE, [workers.simple.vault.address, workers.syrupA.vault.address, workers.syrupB.vault.address], 60],
      signer: signer,
      rpc: RPC,
    });

    return { balancer, workers, signer, other };
  };

  it("testing", async () => {
    const { balancer } = await setup();
  }).timeout(TIMEOUT);
});
