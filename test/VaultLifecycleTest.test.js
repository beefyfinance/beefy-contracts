const { expect } = require("chai");

const { zapNativeToToken, getVaultWant } = require("../utils/testHelpers");

const config = {
  vault: "0x114c5f7f42fB75b7960aa3e4c327f53288360F58",
  vaultContract: "BeefyVaultV5",
  unirouterAddr: "0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F",
  nativeTokenAddr: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
  testAmount: ethers.utils.parseEther("0.1"),
};

describe("VaultLifecycleTest", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();

    const vault = await ethers.getContractAt(config.vaultContract, config.vault);

    const strategyAddr = await vault.strategy();
    const strategy = await ethers.getContractAt("IStrategy", strategyAddr);

    const unirouter = await ethers.getContractAt("IUniswapRouterETH", config.unirouterAddr);

    const want = await getVaultWant(vault);

    // Get some tokens that the vault maximizes.
    await zapNativeToToken({
      amount: config.testAmount,
      want,
      nativeTokenAddr: config.nativeTokenAddr,
      unirouter,
      signer,
    });

    return { signer, other, want, vault, strategy, unirouter };
  };
  it("User can deposit and withdraw from the vault.", async () => {
    const { signer, want, vault } = await setup();

    const wantBal = await want.balanceOf(signer.address);

    await want.approve(vault.address, wantBal);
    await vault.depositAll();
    await vault.withdrawAll();

    const wantBalAfter = await want.balanceOf(signer.address);

    expect(wantBalAfter).to.be.lte(wantBal);
    expect(wantBalAfter).to.be.gt(wantBal.mul(95).div(100));
  });
});
