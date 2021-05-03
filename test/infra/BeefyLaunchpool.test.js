const { expect } = require("chai");

const DURATION = 864000;
const TIMEOUT = 10 * 60 * 1000;

describe("BeefyLaunchpool", async () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("TestToken");
    const stakedToken = await Token.deploy("10000", "Staked Token", "STAKED");
    const rewardToken = await Token.deploy("10000", "Reward Token", "REWARD");
    const otherToken = await Token.deploy("10000", "Other Token", "OTHER");

    const Pool = await ethers.getContractFactory("BeefyLaunchpool");
    const pool = await Pool.deploy(stakedToken.address, rewardToken.address, DURATION);

    return { signer, other, pool, stakedToken, rewardToken, otherToken };
  };

  it("initializes correctly", async () => {
    const { pool, stakedToken, rewardToken } = await setup();
    expect(await pool.stakedToken()).to.equal(stakedToken.address);
    expect(await pool.rewardToken()).to.equal(rewardToken.address);
    expect(await pool.duration()).to.equal(DURATION);
  }).timeout(TIMEOUT);

  it("should not let 'other' account withdraw stuck tokens", async () => {
    const { other, pool, otherToken } = await setup();

    const tx = pool.connect(other).inCaseTokensGetStuck(otherToken.address);

    await expect(tx).to.be.revertedWith("Ownable: caller is not the owner");
  }).timeout(TIMEOUT);

  it("should let owner withdraw 'other' tokens", async () => {
    const { signer, pool, otherToken } = await setup();

    const bal = await otherToken.balanceOf(signer.address);

    await otherToken.transfer(pool.address, bal);
    const balOfPool = await otherToken.balanceOf(pool.address);
    await pool.inCaseTokensGetStuck(otherToken.address);
    const balOfPoolAfter = await otherToken.balanceOf(pool.address);

    const balFinal = await otherToken.balanceOf(signer.address);

    expect(bal).to.equal(balFinal);
    expect(balOfPoolAfter).to.equal(0);
    expect(balOfPool).not.to.equal(balOfPoolAfter);
  }).timeout(TIMEOUT);

  it("should let owner withdraw 'reward' tokens before notify.", async () => {
    const { signer, pool, rewardToken } = await setup();

    const bal = await rewardToken.balanceOf(signer.address);

    await rewardToken.transfer(pool.address, bal);
    const balOfPool = await rewardToken.balanceOf(pool.address);
    await pool.inCaseTokensGetStuck(rewardToken.address);
    const balOfPoolAfter = await rewardToken.balanceOf(pool.address);

    const balFinal = await rewardToken.balanceOf(signer.address);

    expect(bal).to.equal(balFinal);
    expect(balOfPoolAfter).to.equal(0);
    expect(balOfPool).not.to.equal(balOfPoolAfter);
  }).timeout(TIMEOUT);

  it("should let owner withdraw 'stake' tokens before notify.", async () => {
    const { signer, pool, stakedToken } = await setup();

    const bal = await stakedToken.balanceOf(signer.address);

    await stakedToken.transfer(pool.address, bal);
    const balOfPool = await stakedToken.balanceOf(pool.address);
    await pool.inCaseTokensGetStuck(stakedToken.address);
    const balOfPoolAfter = await stakedToken.balanceOf(pool.address);

    const balFinal = await stakedToken.balanceOf(signer.address);

    expect(bal).to.equal(balFinal);
    expect(balOfPoolAfter).to.equal(0);
    expect(balOfPool).not.to.equal(balOfPoolAfter);
  }).timeout(TIMEOUT);

  it("should not let owner withdraw 'stake' tokens after notifyReward()", async () => {
    const { pool, stakedToken } = await setup();

    await pool.notifyRewardAmount();
    const tx = pool.inCaseTokensGetStuck(stakedToken.address);

    await expect(tx).to.be.revertedWith("!staked");
  }).timeout(TIMEOUT);

  it("can only call notifyRewardAmount() once.", async () => {
    const { pool, rewardToken } = await setup();

    await pool.notifyRewardAmount();
    const tx = pool.notifyRewardAmount();

    await expect(tx).to.be.revertedWith("!notified");
  }).timeout(TIMEOUT);
});
