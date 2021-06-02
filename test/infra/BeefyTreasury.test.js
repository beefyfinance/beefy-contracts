const { expect } = require("chai");
const hardhat = require("hardhat");
const ethers = hardhat.ethers;
const deployments = hardhat.deployments;

describe("BeefyTreasury", () => {
  const { provider } = ethers;

  const setup = deployments.createFixture(async () => {
    const namedAccounts   = await hardhat.getNamedAccounts();
    const unnamedAccounts = await hardhat.getUnnamedAccounts();
    const signer = await ethers.getSigner(namedAccounts['deployer']);
    const other  = await ethers.getSigner(unnamedAccounts[0]);

    const Token = await ethers.getContractFactory("TestToken");
    const token = await Token.deploy("10000", "Test Token", "TEST");

    const Treasury = await ethers.getContractFactory("BeefyTreasury");
    const treasury = await Treasury.deploy();

    return { signer, other, token, treasury };
  });

  it("receives BNB correctly", async () => {
    const { signer, treasury } = await setup();
    const value = 10000000000;

    const balanceBefore = await provider.getBalance(treasury.address);
    await signer.sendTransaction({ to: treasury.address, value });
    const balanceAfter = await provider.getBalance(treasury.address);

    expect(balanceBefore).to.equal(0);
    expect(balanceAfter).to.equal(value);
  });

  it("owner can send BNB correctly", async () => {
    const { signer, other, treasury } = await setup();
    const value = 10000000000;
    await signer.sendTransaction({ to: treasury.address, value });

    const balanceBefore = await provider.getBalance(other.address);
    await treasury.withdrawNative(other.address, value);
    const balanceAfter = await provider.getBalance(other.address);

    expect(balanceAfter).to.equal(balanceBefore.add(value));
  });

  it("other account can't send BNB", async () => {
    const { other, treasury } = await setup();

    const tx = treasury.connect(other).withdrawNative(other.address, 0);

    await expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("receives ERC20 correctly", async () => {
    const { token, treasury } = await setup();
    const value = 1000;

    const balanceBefore = await token.balanceOf(treasury.address);
    await token.transfer(treasury.address, value);
    const balanceAfter = await token.balanceOf(treasury.address);

    expect(balanceAfter).to.equal(balanceBefore.add(value));
  });

  it("owner can send ERC20 correctly", async () => {
    const { signer, token, treasury } = await setup();
    const value = 1000;
    await token.transfer(treasury.address, value);

    const balanceBefore = await token.balanceOf(signer.address);
    await treasury.withdrawTokens(token.address, signer.address, value);
    const balanceAfter = await token.balanceOf(signer.address);

    expect(balanceAfter).to.equal(balanceBefore.add(value));
  });

  it("other account can't send ERC20", async () => {
    const { other, token, treasury } = await setup();

    const tx = treasury.connect(other).withdrawTokens(token.address, other.address, 0);

    await expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
  });
});
