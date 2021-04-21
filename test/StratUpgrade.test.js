const { expect } = require("chai");

const config = {
  vault: "0x71b5852857b85D5096d4288AD6d293F217d8e162",
};

describe("BeefyRefund", () => {
  const setup = async () => {
    const [signer] = await ethers.getSigners();

    const vault = await ethers.getContractAt("BeefyVaultV5", config.vault);

    const strategyAddr = await vault.strategy();
    const stratCandidate = await vault.stratCandidate();

    const strategy = await ethers.getContractAt("IStrategy", strategyAddr);
    const candidate = await ethers.getContractAt("IStrategy", stratCandidate.implementation);

    return { signer, vault, strategy, candidate };
  };

  it("Upgrades correctly", async () => {
    const { signer, vault, strategy, candidate } = await setup();

    // expect(await beefyRefund.token()).to.equal(token.address);
    // expect(await beefyRefund.mootoken()).to.equal(mootoken.address);
    // expect(await beefyRefund.pricePerFullShare()).to.equal(pricePerFullShare);
  });
});

// 3. Checks balances before upgrade.

// 4. Calls upgrade.

// 5. Checks balances afterwards

// 6. Checks that harvest works

// 7. Checks that panic works.
