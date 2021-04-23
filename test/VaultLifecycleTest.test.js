const { expect } = require("chai");

const { delay } = require("../utils/timeHelpers");

const config = {
  vault: "0x6BE4741AB0aD233e4315a10bc783a7B923386b71",
  vaultContract: "BeefyVaultV5",
  unirouter: "0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F",
  nativeTokenAddr: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
  testAmount: ethers.utils.parseEther("0.1"),
};

async function zap(amount, vault, router, signer) {}

async function getWant(vault) {
  let wantAddr;

  try {
    wantAddr = await vault.token();
  } catch (e) {
    try {
      wantAddr = await vault.want();
    } catch (e) {
      wantAddr = config.nativeTokenAddr;
    }
  }

  const want = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", wantAddr);

  return want;
}

describe("VaultLifecycleTest", () => {
  const setup = async () => {
    const [signer, other] = await ethers.getSigners();

    const vault = await ethers.getContractAt(config.vaultContract, config.vault);

    const strategyAddr = await vault.strategy();
    const strategy = await ethers.getContractAt("IStrategy", strategyAddr);

    // 1. Get the want of a vault.
    const want = await getWant(vault);

    // A. Figure out if it's WBNB in which case wrap it.
    if (want.address == config.nativeTokenAddr) {
      const nativeToken = await ethers.getContractAt("IWBNB", want.address);
      await nativeToken.deposit({ value: config.testAmount });
    }

    // B. Figure out if it's a single token. In that case buy it and return.

    // 3. Figure out if

    // await router.swapExactETHForTokens(0, [WBNB, BTCB], signer.address, 5000000000, { value: DEPOSIT_AMOUNT });

    return { signer, other, vault, strategy };
  };
  it("User can deposit and withdraw.", async () => {
    const { signer, other, vault, strategy } = await setup();
    // get want into our wallet.
    let amount = 0,
      router = 0;

    await zap(amount, vault, router, signer);

    // deposit into vault

    // withdraw from vault

    // assert that balances are correct
  });
});

// zap function that goes from
