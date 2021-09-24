const { expect } = require("chai");

describe("BeefyFeeBatchV2", () => {
  const { provider } = ethers;

  const setup = async () => {
    const [signer, other] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("TestToken");
    const token = await Token.deploy("10000", "Test Token", "TEST");

    const Treasury = await ethers.getContractFactory("BeefyTreasury");
    const treasury = await Treasury.deploy();

    return { signer, other, token, treasury };
  };

  it("receives BNB correctly", async () => {
    const { signer, treasury } = await setup();
    const value = 10000000000;

    const balanceBefore = await provider.getBalance(treasury.address);
    await signer.sendTransaction({ to: treasury.address, value });
    const balanceAfter = await provider.getBalance(treasury.address);

    expect(balanceBefore).to.equal(0);
    expect(balanceAfter).to.equal(value);
  });
});
