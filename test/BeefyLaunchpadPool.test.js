const { expect } = require("chai");

const DURATION = 864000;
const CAP_PER_ADDR = "100";

describe("BeefyLaunchpadPool", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("TestToken");
    const stakedToken = await Token.deploy("10000", "Staked Token", "STAKED");
    const rewardToken = await Token.deploy("10000", "Reward Token", "REWARD");
    const otherToken = await Token.deploy("10000", "Other Token", "OTHER");

    const Pool = await ethers.getContractFactory("BeefyLaunchpadPool");
    const pool = await Pool.deploy(stakedToken.address, rewardToken.address, DURATION, CAP_PER_ADDR);

    return { signer, other, pool, stakedToken, rewardToken, otherToken };
  };

  it("initializes correctly", async () => {
    const { pool, stakedToken, rewardToken } = await setup();
    expect(await pool.stakedToken()).to.equal(stakedToken.address);
    expect(await pool.rewardToken()).to.equal(rewardToken.address);
    expect(await pool.duration()).to.equal(DURATION);
    expect(await pool.capPerAddr()).to.equal(CAP_PER_ADDR);
  });

  it("should revert deposit above cap", async () => {
    const { pool, stakedToken } = await setup();
    const largeAmount = "100000000000000000000000";
    await stakedToken.approve(pool.address, largeAmount);
    const tx = pool.stake(largeAmount);

    await expect(tx).to.be.revertedWith("Cap reached");
  });

  it("should revert on multiple deposits that add up to more than the cap", async () => {
    const { pool, stakedToken } = await setup();
    const amount = CAP_PER_ADDR;
    await stakedToken.approve(pool.address, amount);

    let tx = pool.stake(amount);
    await expect(tx).not.to.be.reverted;

    await stakedToken.approve(pool.address, "1");
    tx = pool.stake("1");
    await expect(tx).to.be.revertedWith("Cap reached");
  });

  it("should accept deposit equal to the cap", async () => {
    const { signer, pool, stakedToken } = await setup();
    const amount = CAP_PER_ADDR;
    await stakedToken.approve(pool.address, amount);

    const balance = await pool.balanceOf(signer.address);
    const tx = pool.stake(amount);

    await expect(tx).not.to.be.reverted;
    const balanceAfter = await pool.balanceOf(signer.address);

    expect(balance).to.be.below(balanceAfter);
    expect(balanceAfter).to.equal(amount);
  });

  it("should accept deposit smaller than the cap", async () => {
    const { signer, pool, stakedToken } = await setup();
    const smallAmount = "1";
    await stakedToken.approve(pool.address, smallAmount);

    const balance = await pool.balanceOf(signer.address);
    const tx = pool.stake(smallAmount);

    await expect(tx).not.to.be.reverted;
    const balanceAfter = await pool.balanceOf(signer.address);

    expect(balance).to.be.below(balanceAfter);
    expect(balanceAfter).to.equal(smallAmount);
  });

  it("should not let other account withdraw stuck tokens", async () => {
    const { other, pool, otherToken } = await setup();

    const tx = pool.connect(other).inCaseTokensGetStuck(otherToken.address);

    await expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("should not let owner withdraw staked tokens", async () => {
    const { pool, stakedToken } = await setup();

    const tx = pool.inCaseTokensGetStuck(stakedToken.address);

    await expect(tx).to.be.revertedWith("!staked");
  });

  it("should not let owner withdraw reward tokens", async () => {
    const { pool, rewardToken } = await setup();

    const tx = pool.inCaseTokensGetStuck(rewardToken.address);

    await expect(tx).to.be.revertedWith("!reward");
  });

  it("should let owner withdraw other tokens", async () => {
    const { pool, otherToken } = await setup();

    const bal = await otherToken.balanceOf(pool.address);

    await otherToken.transfer(pool.address, "100");
    await pool.inCaseTokensGetStuck(otherToken.address);

    const balAfter = await otherToken.balanceOf(pool.address);

    expect(bal).to.equal(balAfter);
  });
});
