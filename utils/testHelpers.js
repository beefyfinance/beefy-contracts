const hardhat = require("hardhat");
const ethers = hardhat.ethers;

// TODO: Handle custom LPs (Like Belt LPs)

async function zapNativeToToken({ amount, want, nativeTokenAddr, unirouter, recipient }) {
  let isLpToken, lpPair, token0, token1;

  // handle wbnb
  if (want.address == nativeTokenAddr) {
    const nativeToken = await ethers.getContractAt("IWBNB", want.address);
    await nativeToken.deposit({ value: amount });

    return;
  }

  try {
    lpPair = await ethers.getContractAt("IUniswapV2Pair", want.address);

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
      const token0BalBefore = await token0.balanceOf(recipient);

      await swapNativeForToken({ unirouter, token: token0, recipient, nativeTokenAddr, amount: amount.div(2) });
      await swapNativeForToken({ unirouter, token: token1, recipient, nativeTokenAddr, amount: amount.div(2) });

      const token0Bal = await token0.balanceOf(recipient);
      const token1Bal = await token1.balanceOf(recipient);

      await token0.approve(unirouter.address, token0Bal);
      await token1.approve(unirouter.address, token1Bal);

      await unirouter.addLiquidity(token0.address, token1.address, token0Bal, token1Bal, 1, 1, recipient, 5000000000);
    } catch (e) {
      console.log("Could not add liquidity", e);
    }
  } else {
    await swapNativeForToken({ unirouter, token: want, recipient, nativeTokenAddr, amount });
  }
}

async function swapNativeForToken({ unirouter, amount, nativeTokenAddr, token, recipient }) {
  if (token.address === nativeTokenAddr) return;

  try {
    await unirouter.swapExactETHForTokens(0, [nativeTokenAddr, token.address], recipient, 5000000000, {
      value: amount,
    });
  } catch (e) {
    console.log(`Could not swap for ${token.address}: ${e}`);
  }
}

async function logTokenBalance(token, wallet) {
  const balance = await token.balanceOf(wallet);
  console.log(`Balance: ${ethers.utils.formatEther(balance.toString())}`);
}

async function getVaultWant(vault) {
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

async function unpauseIfPaused(strat) {
  const isPaused = await strat.paused();
  if (isPaused) {
    await strat.unpause();
  }
}

function getUnirouterInterface(address) {
  switch (address) {
    case "0xA52aBE4676dbfd04Df42eF7755F01A3c41f28D27":
      return "IUniswapRouterAVAX";
    default:
      return "IUniswapRouterETH";
  }
}

function getWrappedNativeAddr(networkId) {
  switch (networkId) {
    case "bsc":
      return "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
    case "avax":
      return "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7";
    case "polygon":
      return "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
    case "heco":
      return "0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F";
    default:
      throw new Error("Unknown network.");
  }
}

module.exports = {
  zapNativeToToken,
  swapNativeForToken,
  getVaultWant,
  logTokenBalance,
  unpauseIfPaused,
  getUnirouterInterface,
  getWrappedNativeAddr,
};
