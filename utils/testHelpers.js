const hardhat = require("hardhat");
const ethers = hardhat.ethers;

// TODO: Handle custom LPs (Like Belt LPs)

const zapNativeToToken = async ({ amount, want, nativeTokenAddr, unirouter, swapSignature, recipient }) => {
  let isLpToken, lpPair, token0, token1;

  try {
    lpPair = await ethers.getContractAt(
      "contracts/BIFI/interfaces/common/IUniswapV2Pair.sol:IUniswapV2Pair",
      want.address
    );

    const token0Addr = await lpPair.token0();
    token0 = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", token0Addr);

    const token1Addr = await lpPair.token1();
    token1 = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", token1Addr);
    isLpToken = true;
  } catch (e) {
    isLpToken = false;
  }

  if (isLpToken) {
    try {
      await swapNativeForToken({
        unirouter,
        token: token0,
        recipient,
        nativeTokenAddr,
        amount: amount.div(2),
        swapSignature,
      });
      await swapNativeForToken({
        unirouter,
        token: token1,
        recipient,
        nativeTokenAddr,
        amount: amount.div(2),
        swapSignature,
      });

      const token0Bal = await token0.balanceOf(recipient);
      const token1Bal = await token1.balanceOf(recipient);

      await token0.approve(unirouter.address, token0Bal);
      await token1.approve(unirouter.address, token1Bal);

      await unirouter.addLiquidity(token0.address, token1.address, token0Bal, token1Bal, 1, 1, recipient, 5000000000);
    } catch (e) {
      console.log("Could not add LP liquidity.", e);
    }
  } else {
    try {
      await swapNativeForToken({ unirouter, token: want, recipient, nativeTokenAddr, amount, swapSignature });
    } catch (e) {
      console.log("Could not swap for want.", e);
    }
  }
};

const swapNativeForToken = async ({ unirouter, amount, nativeTokenAddr, token, recipient, swapSignature }) => {
  if (token.address === nativeTokenAddr) {
    await wrapNative(amount, nativeTokenAddr);
    return;
  }

  try {
    await unirouter[swapSignature](0, [nativeTokenAddr, token.address], recipient, 5000000000, {
      value: amount,
    });
  } catch (e) {
    console.log(`Could not swap for ${token.address}: ${e}`);
  }
};

const logTokenBalance = async (token, wallet) => {
  const balance = await token.balanceOf(wallet);
  console.log(`Balance: ${ethers.utils.formatEther(balance.toString())}`);
};

const getVaultWant = async (vault, wnative) => {
  let wantAddr;

  try {
    wantAddr = await vault.token();
  } catch (e) {
    try {
      wantAddr = await vault.want();
    } catch (e) {
      wantAddr = wnative;
    }
  }

  const want = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", wantAddr);

  return want;
};

const unpauseIfPaused = async (strat, keeper) => {
  const isPaused = await strat.paused();
  if (isPaused) {
    await strat.connect(keeper).unpause();
  }
};

const getUnirouterData = address => {
  switch (address) {
    case "0xA52aBE4676dbfd04Df42eF7755F01A3c41f28D27":
    case "0x60aE616a2155Ee3d9A68541Ba4544862310933d4":
      return {
        interface: "IUniswapRouterAVAX",
        swapSignature: "swapExactAVAXForTokens",
      };
    case "0xf38a7A7Ac2D745E2204c13F824c00139DF831FFf":
      return {
        interface: "IUniswapRouterMATIC",
        swapSignature: "swapExactMATICForTokens",
      };
    case "0xA63B831264183D755756ca9AE5190fF5183d65D6":
      return {
        interface: "IUniswapRouterBNB",
        swapSignature: "swapExactBNBForTokens",
      };
    default:
      return {
        interface: "IUniswapRouterETH",
        swapSignature: "swapExactETHForTokens",
      };
  }
};

const wrapNative = async (amount, wNativeAddr) => {
  const wNative = await ethers.getContractAt("IWrappedNative", wNativeAddr);
  await wNative.deposit({ value: amount });
};

module.exports = {
  zapNativeToToken,
  swapNativeForToken,
  getVaultWant,
  logTokenBalance,
  unpauseIfPaused,
  getUnirouterData,
};
