const { expect } = require("chai");

const { nowInSeconds, delay } = require("../utils/timeHelpers");

const config = {
  vault: "0x044e87f30bd9bD961c04028aC69155493E1b9eD0",
};

describe("StratUpgrade", () => {
  const setup = async () => {
    const vault = await ethers.getContractAt("BeefyVaultV5", config.vault);

    const strategyAddr = await vault.strategy();
    const stratCandidate = await vault.stratCandidate();

    const strategy = await ethers.getContractAt("IStrategy", strategyAddr);
    const candidate = await ethers.getContractAt("IStrategy", stratCandidate.implementation);

    return { vault, strategy, candidate };
  };

  it("Upgrades correctly", async () => {
    const { vault, strategy, candidate } = await setup();

    // check that balances are transfered correctly.
    console.log("Checking Balances");
    const vaultBal = await vault.balance();
    const strategyBal = await strategy.balanceOf();
    const candidateBal = await candidate.balanceOf();

    await vault.upgradeStrat();

    const vaultBalAfter = await vault.balance();
    const strategyBalAfter = await strategy.balanceOf();
    const candidateBalAfter = await candidate.balanceOf();

    expect(vaultBal).to.equal(vaultBalAfter);
    expect(strategyBal).not.to.equal(strategyBalAfter);
    expect(strategyBal).to.equal(candidateBalAfter);
    expect(candidateBal).not.to.equal(candidateBalAfter);
    expect(candidateBal).to.equal(strategyBalAfter);

    // check that harvesting works.
    console.log("Checking Harvest");
    await delay(10000);

    let tx = candidate.harvest();
    await expect(tx).not.to.be.reverted;

    // check that panic works.
    console.log("Checking Panic");
    const balBeforePanic = await candidate.balanceOf();

    tx = candidate.panic();
    await expect(tx).not.to.be.reverted;

    const balAfterPanic = await candidate.balanceOf();

    expect(balBeforePanic).to.equal(balAfterPanic);
  });
});
