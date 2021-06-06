import { Contract } from "@ethersproject/contracts";
import hardhat from "hardhat";
import { BigNumber, Signer } from "ethers";
const ethers = hardhat.ethers;

// TODO: Handle custom LPs (Like Belt LPs)
type SwapArgs = {
  amount: BigNumber,
  want: Contract,
  nativeTokenAddr: string,
  unirouter: Contract,
  swapSignature: string,
  signer: Signer
};

type LpRoutes = {
  tokenToLp0?: string[],
  tokenToLp1?: string[]
}

const zapNativeToToken = async ({ amount, want, nativeTokenAddr, unirouter, swapSignature, signer, tokenToLp0, tokenToLp1 }: SwapArgs & LpRoutes) => {
  let lpPair: Contract;
  let token0: Contract | null = null;
  let token1: Contract | null = null;

  let recipient = await signer.getAddress();

  try {
    lpPair = await ethers.getContractAt(
      "contracts/BIFI/interfaces/common/IUniswapV2Pair.sol:IUniswapV2Pair",
      want.address,
      signer
    );

    const token0Addr = await lpPair.token0();
    token0 = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", token0Addr, signer);

    const token1Addr = await lpPair.token1();
    token1 = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", token1Addr, signer);
  } catch (e) {}

  if (token0 && token1) {
    try {
      await swapNativeForToken({
        unirouter,
        want: token0,
        signer,
        nativeTokenAddr,
        amount: amount.div(2),
        swapSignature,
        route: tokenToLp0,
      });
      await swapNativeForToken({
        unirouter,
        want: token1,
        signer,
        nativeTokenAddr,
        amount: amount.div(2),
        swapSignature,
        route: tokenToLp1,
      });

      const token0Bal = await token0.balanceOf(recipient);
      const token1Bal = await token1.balanceOf(recipient);

      await token0.approve(unirouter.address, token0Bal);
      await token1.approve(unirouter.address, token1Bal);

      await unirouter.addLiquidity(token0.address, token1.address, token0Bal, token1Bal, 0, 0, recipient, 5000000000);
    } catch (e) {
      console.log("Could not add LP liquidity.", e);
    }
  } else {
    try {
      await swapNativeForToken({ unirouter, want, signer, nativeTokenAddr, amount, swapSignature });
    } catch (e) {
      console.log("Could not swap for want.", e);
    }
  }
};

const swapNativeForToken = async ({ unirouter, amount, nativeTokenAddr, want:token, signer, swapSignature, route }:SwapArgs & {route?:string[]}) => {
  let recipient = await signer.getAddress();

  if (token.address === nativeTokenAddr) {
    await wrapNative(amount, nativeTokenAddr, signer);
    return;
  }

  try {
    let swapRoute = route ?? [nativeTokenAddr, token.address];
    await unirouter[swapSignature](0, swapRoute, recipient, 5000000000, {
      value: amount,
    });
  } catch (e) {
    console.log(`Could not swap for ${token.address}: ${e}`);
  }
};

const logTokenBalance = async (token:Contract, wallet:string) => {
  const balance = await token.balanceOf(wallet);
  console.log(`Balance: ${ethers.utils.formatEther(balance.toString())}`);
};

const getVaultWant = async (vault:Contract, defaultTokenAddress:string) => {
  let wantAddr;

  try {
    wantAddr = await vault.token();
  } catch (e) {
    try {
      wantAddr = await vault.want();
    } catch (e) {
      wantAddr = defaultTokenAddress;
    }
  }

  const want = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", wantAddr, vault.signer);

  return want;
};

const unpauseIfPaused = async (strat:Contract) => {
  const isPaused = await strat.paused();
  if (isPaused) {
    await strat.unpause();
  }
};

const getUnirouterData = (address:string) => {
  switch (address) {
    case "0xA52aBE4676dbfd04Df42eF7755F01A3c41f28D27":
      return {
        interface: "IUniswapRouterAVAX",
        swapSignature: "swapExactAVAXForTokens",
      };
    case "0xf38a7A7Ac2D745E2204c13F824c00139DF831FFf":
      return {
        interface: "IUniswapRouterMATIC",
        swapSignature: "swapExactMATICForTokens",
      };
    default:
      return {
        interface: "IUniswapRouterETH",
        swapSignature: "swapExactETHForTokens",
      };
  }
};

const getWrappedNativeAddr = (networkId:string) => {
  switch (networkId) {
    case "bsc":
      return "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
    case "avax":
      return "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7";
    case "polygon":
      return "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
    case "heco":
      return "0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F";
    case "fantom":
      return "0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83";
    default:
      throw new Error("Unknown network.");
  }
};

const wrapNative = async (amount:BigNumber, wNativeAddr:string, recipient:Signer) => {
  const wNative = await ethers.getContractAt("IWrappedNative", wNativeAddr, recipient);
  await wNative.deposit({ value: amount });
};

export {
  zapNativeToToken,
  swapNativeForToken,
  getVaultWant,
  logTokenBalance,
  unpauseIfPaused,
  getUnirouterData,
  getWrappedNativeAddr,
};
