const { expect } = require("chai");

const { predictAddresses } = require("../utils/predictAddresses");

// TOKENS
const WBNB = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
const CAKE = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82";

// SCs
const SMARTCHEFS = [
  "0x90F995b9d46b32c4a1908A8c6D0122e392B3Be97",
  "0xdc8c45b7F3747Ca9CaAEB3fa5e0b5FCE9430646b",
  "0x9c4EBADa591FFeC4124A7785CAbCfb7068fED2fb"
];

// CONFIG
const VAULT_NAME = "Moo Smart Cake";
const VAULT_SYMBOL = "mooSmartCake";
const TIMEOUT = 10 * 60 * 1000;
const DELAY = 5;

// Error Codes
const OWNABLE_ERROR = "Ownable: caller is not the owner";
const PAUSED_ERROR = "Pausable: paused";

describe("Migrate SmartCake", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();
    
    const ERC20 = await artifacts.readArtifact("ERC20");
    const contracts = {
      wbnb: await ethers.getContractAt(ERC20.abi, WBNB),
      cake: await ethers.getContractAt(ERC20.abi, CAKE)
    };

    return { signer, other, contracts };
  };

  const mockOldArch = async () => {
    const { signer, contracts } = await setup();

    const predictedAddresses = await predictAddresses({ creator: signer.address, rpc: "http://127.0.0.1:8545" });

    const Vault = await ethers.getContractFactory("BeefyVaultV3");
    const vault = await Vault.deploy(CAKE, predictedAddresses.strategy, VAULT_NAME, VAULT_SYMBOL, 0);
    await vault.deployed();
  
    const Strategy = await ethers.getContractFactory("StrategyCakeSmart");
    const strategy = await Strategy.deploy(predictedAddresses.vault, DELAY);
    await strategy.deployed();

    return { vault, strategy };
  }
  
  describe("initialization", () => {
    it("should correctly connect vault/strat on deploy.", async () => {
      const { vault, strategy } = await mockOldArch();

      expect(await vault.strategy()).to.equal(strategy.address);
      expect(await strategy.vault()).to.equal(vault.address);
    }).timeout(TIMEOUT);
  });  
});
