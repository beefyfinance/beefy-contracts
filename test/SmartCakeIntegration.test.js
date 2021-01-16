const { expect } = require("chai");

const { predictAddresses } = require("../utils/predictAddresses");
const { delay } = require("../utils/timeHelpers");

const TIMEOUT = 10 * 60 * 1000;
const DELAY = 2;
const WBNB = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
const CAKE = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";

const SMARTCHEFS = [
  "0x90F995b9d46b32c4a1908A8c6D0122e392B3Be97",
  "0xdc8c45b7F3747Ca9CaAEB3fa5e0b5FCE9430646b",
  "0x9c4EBADa591FFeC4124A7785CAbCfb7068fED2fb",
];

const VAULT_NAME = "Moo Smart Cake";
const VAULT_SYMBOL = "mooSmartCake";

describe("StrategyCakeSmart", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();
    const predictedAddresses = await predictAddresses({ creator: signer.address, rpc: "http://127.0.0.1:8545" });

    const Vault = await ethers.getContractFactory("BeefyVaultV2");
    const vault = await Vault.deploy(CAKE, predictedAddresses.strategy, VAULT_NAME, VAULT_SYMBOL, DELAY);
    await vault.deployed();

    const Strategy = await ethers.getContractFactory("StrategyCakeSmart");
    const strategy = await Strategy.deploy(predictedAddresses.vault, DELAY);
    await strategy.deployed();

    const candidate = await Strategy.deploy(predictedAddresses.vault, DELAY);
    await candidate.deployed();

    const ERC20 = await artifacts.readArtifact("ERC20");
    const tokens = {
      wbnb: new ethers.Contract(WBNB, ERC20.abi, signer),
      cake: new ethers.Contract(CAKE, ERC20.abi, signer),
    };
    return { signer, other, vault, strategy, candidate, tokens };
  };

  it("can deposit in one strategy and withdraw after strat migration", async () => {
    const { signer, vault, strategy, candidate, tokens } = await setup();
    const AMOUNT = "10000";
    const FEE = "10";

    const balBefore = await tokens.cake.balanceOf(signer.address);

    await tokens.cake.approve(vault.address, AMOUNT);
    await vault.deposit(AMOUNT);
    await vault.proposeStrat(candidate.address);
    await delay(3000);
    await strategy.retireStrat();
    await vault.upgradeStrat();
    await vault.withdrawAll();

    const balAfter = await tokens.cake.balanceOf(signer.address);

    expect(balAfter).to.equal(balBefore.sub(FEE));
  }).timeout(TIMEOUT);

  it("can harvest in one strategy and then harvest after migration", async () => {
    const { signer, vault, strategy, candidate, tokens } = await setup();
    const AMOUNT = "10000";
    const FEE = "10";

    const balBefore = await tokens.cake.balanceOf(signer.address);

    await tokens.cake.approve(vault.address, AMOUNT);
    await vault.deposit(AMOUNT);
    await strategy.harvest(0, { gasLimit: 3500000 });
    await vault.proposeStrat(candidate.address);
    await delay(3000);
    await strategy.retireStrat();
    await vault.upgradeStrat();
    await strategy.harvest(0, { gasLimit: 3500000 });
    await vault.withdrawAll();

    const balAfter = await tokens.cake.balanceOf(signer.address);

    expect(balAfter).to.equal(balBefore.sub(FEE));
  }).timeout(TIMEOUT);
});
