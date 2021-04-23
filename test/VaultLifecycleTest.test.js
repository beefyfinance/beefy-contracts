const { expect } = require("chai");

const { delay } = require("../utils/timeHelpers");

const config = {
  vault: "0x8da7167860EDfc2bFfd790f217AB5e398803Bbc8",
  vaultContract: "BeefyVaultV5",
  unirouterAddr: "0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F",
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

    const unirouter = await ethers.getContractAt("IUniswapRouterETH", config.unirouterAddr);

    // 1. Get the want of a vault.
    const want = await getWant(vault);

    // A. Figure out if it's WBNB in which case wrap it.
    if (want.address == config.nativeTokenAddr) {
      const nativeToken = await ethers.getContractAt("IWBNB", want.address);
      await nativeToken.deposit({ value: config.testAmount });
    }

    // B. Figure out if it's a single token. In that case buy it and return.
    let isLpToken, lpPair, token0, token1;
    try {
      lpPair = await ethers.getContractAt("IUniswapV2Pair", want.address);
      token0 = await lpPair.token0();
      token1 = await lpPair.token1();
      isLpToken = true;
    } catch (e) {
      isLpToken = false;
    }

    if (isLpToken) {
    } else {
      const wantBal = await want.balanceOf(signer.address);
      await unirouter.swapExactETHForTokens(0, [config.nativeTokenAddr, want.address], signer.address, 5000000000, {
        value: config.testAmount,
      });
      const wantBalAfter = await want.balanceOf(signer.address);
    }

    // 3. Figure out if

    //

    return { signer, other, vault, strategy, unirouter };
  };
  it("User can deposit and withdraw.", async () => {
    const { signer, other, vault, strategy } = await setup();
    // get want into our wallet.

    // await zap(amount, vault, router, signer);

    // deposit into vault

    // withdraw from vault

    // assert that balances are correct
  });
});

// zap function that goes from
