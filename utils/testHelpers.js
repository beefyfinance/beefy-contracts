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

module.exports = { zapNativeToToken, swapNativeForToken, getVaultWant, logTokenBalance };
