const { expect } = require("chai");
const { waffle } = require("hardhat");
const { deployMockContract } = waffle;

const IVault = require("../artifacts/contracts/BIFI/interfaces/beefy/IVault.sol/IVault.json");
const ISmartChef = require("../artifacts/contracts/BIFI/interfaces/pancake/ISmartChef.sol/ISmartChef.json");

describe("StrategyCakeOutput", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();

    const mockVault = await deployMockContract(signer, IVault.abi);
    const mockSmartChef = await deployMockContract(signer, ISmartChef.abi);

    console.log(mockVault.address, "So");
    const Strategy = await ethers.getContractFactory("StrategyCakeOutput");
    const strategy = await Strategy.deploy(mockSmartChef.address, mockVault.address);

    return { signer, other, mockVault, mockSmartChef, strategy };
  };

  it("deposit can't be called by a random account", async () => {
    const { signer, other, mockVault, mockSmartChef, strategy } = await setup();
    console.log(strategy.address, mockVault.address);
  });

  it("deposit can be called by its vault", () => {});
});
