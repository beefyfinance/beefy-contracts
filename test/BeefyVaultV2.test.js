const { expect } = require("chai");
const { waffle } = require("hardhat");
const { deployMockContract } = waffle;

const { nowInSeconds, delay } = require("../utils/timeHelpers");

const TIMEOUT = 10 * 60 * 1000;

const VAULT_NAME = "Moo Cake";
const VAULT_SYMBOL = "mooCake";
const APPROVAL_DELAY = 5;
const { AddressZero } = ethers.constants;

describe("BeefyVaultV2", () => {
  const setup = async () => {
    const ERC20 = await artifacts.readArtifact("ERC20");
    const IStrategy = await artifacts.readArtifact("IStrategy");

    const [signer, other] = await ethers.getSigners();
    const mockToken = await deployMockContract(signer, ERC20.abi);
    await mockToken.mock.name.returns("Mock Token");
    await mockToken.mock.symbol.returns("MCK");
    await mockToken.mock.decimals.returns(18);

    const mockStrategy = await deployMockContract(signer, IStrategy.abi);
    const mockCandidate = await deployMockContract(signer, IStrategy.abi);

    const Vault = await ethers.getContractFactory("BeefyVaultV2");
    const vault = await Vault.deploy(mockToken.address, mockStrategy.address, VAULT_NAME, VAULT_SYMBOL, APPROVAL_DELAY);

    const mocks = {
      token: mockToken,
      strategy: mockStrategy,
      candidate: mockCandidate
    };

    return { signer, other, vault, mocks };
  };

  it("Initializes values correctly", async () => {
    const { vault, mocks } = await setup();

    expect(await vault.name()).to.equal(VAULT_NAME);
    expect(await vault.symbol()).to.equal(VAULT_SYMBOL);
    expect(await vault.decimals()).to.equal(await mocks.token.decimals());
    expect(await vault.approvalDelay()).to.equal(APPROVAL_DELAY);
    expect(await vault.strategy()).to.equal(mocks.strategy.address);
  }).timeout(TIMEOUT);

  it("returns the correct balance()", async () => {
    const { vault, mocks } = await setup();
    await mocks.token.mock.balanceOf.returns(0);
    await mocks.strategy.mock.balanceOf.returns(0);
    expect(await vault.balance()).to.equal(0);

    await mocks.token.mock.balanceOf.returns(10);
    await mocks.strategy.mock.balanceOf.returns(0);
    expect(await vault.balance()).to.equal(10);

    await mocks.token.mock.balanceOf.returns(10);
    await mocks.strategy.mock.balanceOf.returns(10);
    expect(await vault.balance()).to.equal(20);
  }).timeout(TIMEOUT);

  it("returns the correct available() tokens", async () => {
    const { vault, mocks } = await setup();
    await mocks.token.mock.balanceOf.withArgs(vault.address).returns(0);
    expect(await vault.available()).to.equal(await mocks.token.balanceOf(vault.address));

    await mocks.token.mock.balanceOf.withArgs(vault.address).returns(1000);
    expect(await vault.available()).to.equal(await mocks.token.balanceOf(vault.address));
  }).timeout(TIMEOUT);

  describe("strat upgrade", () => {
    it("proposeStrat: owner can correctly propose a new strat candidate.", async () => {
      const { vault, mocks } = await setup();

      const candidateBefore = await vault.stratCandidate();

      await vault.proposeStrat(mocks.candidate.address);

      const candidateAfter = await vault.stratCandidate();
      // Hardhat doesn't calculate 'now' correctly. Have to add a buffer to this now.
      const now = nowInSeconds() + 50;

      expect(candidateBefore.implementation).to.equal(AddressZero);
      expect(candidateAfter.implementation).to.equal(mocks.candidate.address);
      expect(candidateAfter.proposedTime).to.be.lte(now);
    }).timeout(TIMEOUT);

    it("proposeStrat: it fires the correct event.", async () => {
      const { vault, mocks } = await setup();

      const tx = vault.proposeStrat(mocks.candidate.address);

      await expect(tx)
        .to.emit(vault, "NewStratCandidate")
        .withArgs(mocks.candidate.address);
    }).timeout(TIMEOUT);

    it("proposeStrat: other account can't propose a strat.", async () => {
      const { other, vault, mocks } = await setup();

      const tx = vault.connect(other).proposeStrat(mocks.candidate.address);

      await expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
    }).timeout(TIMEOUT);

    it("upgradeStrat: can't upgrade when current strat is active", async () => {
      const { vault, mocks } = await setup();
      await mocks.strategy.mock.retired.returns(false);

      const tx = vault.upgradeStrat();

      await expect(tx).to.be.revertedWith("Current strat is active");
    }).timeout(TIMEOUT);

    it("upgradeStrat: can't upgrade when the candidate implementation is 0x0", async () => {
      const { vault, mocks } = await setup();
      await mocks.strategy.mock.retired.returns(true);

      const stratCandidate = await vault.stratCandidate();

      const tx = vault.upgradeStrat();

      expect(stratCandidate.implementation).to.equal(AddressZero);
      await expect(tx).to.be.revertedWith("There is no candidate");
    }).timeout(TIMEOUT);

    it("upgradeStrat: can't upgrade when approveDelay hasn't transcurred", async () => {
      const { vault, mocks } = await setup();
      await mocks.strategy.mock.retired.returns(true);
      await vault.proposeStrat(mocks.candidate.address);

      const tx = vault.upgradeStrat();

      await expect(tx).to.be.revertedWith("Delay has not passed");
    }).timeout(TIMEOUT);

    it("upgradeStrat: other account can't call upgradeStrat", async () => {
      const { other, vault } = await setup();

      const tx = vault.connect(other).upgradeStrat();

      await expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
    }).timeout(TIMEOUT);

    it("upgradeStrat: upgrading changes current strat and nulls the candidate", async () => {
      const { vault, mocks } = await setup();
      await mocks.strategy.mock.retired.returns(true);
      await vault.proposeStrat(mocks.candidate.address);
      await delay((APPROVAL_DELAY + 1) * 1000);
      await mocks.token.mock.balanceOf.returns(0);
      await mocks.token.mock.transfer.returns(true);
      await mocks.candidate.mock.deposit.returns();

      const strategyBefore = await vault.strategy();
      const candidateBefore = await vault.stratCandidate();

      await vault.upgradeStrat();

      const strategyAfter = await vault.strategy();
      const candidateAfter = await vault.stratCandidate();

      expect(strategyBefore).to.not.equal(strategyAfter);
      expect(strategyAfter).to.equal(mocks.candidate.address);
      expect(candidateBefore.implementation).to.not.equal(candidateAfter.implementation);
      expect(candidateAfter.implementation).to.equal(AddressZero);
    }).timeout(TIMEOUT);

    it("upgradeStrat: upgrading emits an UpgradeStrat event.", async () => {
      const { vault, mocks } = await setup();
      await mocks.strategy.mock.retired.returns(true);
      await vault.proposeStrat(mocks.candidate.address);
      await delay((APPROVAL_DELAY + 1) * 1000);
      await mocks.token.mock.balanceOf.returns(0);
      await mocks.token.mock.transfer.returns(true);
      await mocks.candidate.mock.deposit.returns();

      const tx = vault.upgradeStrat();

      await expect(tx)
        .to.emit(vault, "UpgradeStrat")
        .withArgs(mocks.candidate.address);
    }).timeout(TIMEOUT);
  });
});
