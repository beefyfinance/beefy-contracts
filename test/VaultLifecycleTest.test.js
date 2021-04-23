const { expect } = require("chai");

const { zapNativeToToken, getVaultWant } = require("../utils/testHelpers");

const config = {
  vault: "0x1Ae7E76e2Eb74070774bbd9EAC75585452f24C23",
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

    await zapNativeToToken({
      amount: config.testAmount,
      want,
      nativeTokenAddr: config.nativeTokenAddr,
      unirouter,
      signer,
    });

    return { signer, other, vault, strategy, unirouter };
  };
  it("User can deposit and withdraw.", async () => {
    const { signer, other, vault, strategy, unirouter } = await setup();

    // await zap(amount, vault, router, signer);

    // deposit into vault

    // withdraw from vault

    // assert that balances are correct
  });
});

// zap function that goes from
