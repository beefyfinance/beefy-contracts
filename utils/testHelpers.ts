import { Contract } from "@ethersproject/contracts";
import hardhat from "hardhat";
import { BigNumber, Signer } from "ethers";
import { BeefyVaultV5, BeefyVaultV6, IERC20, IERC20__factory } from "../typechain";
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

const getVaultWant = async (vault:BeefyVaultV5|BeefyVaultV6, defaultTokenAddress:string) => {
  let wantAddr;

  try {
    if ("token" in vault) {
      wantAddr = await vault.token();
    }
    else {
      wantAddr = await vault.want();
    }
  }
  catch (e) {
    console.warn(e);
    console.warn("Using default token");
    wantAddr = defaultTokenAddress;
  }

  return IERC20__factory.connect(wantAddr, vault.signer);
};

const unpauseIfPaused = async (strat:Contract, keeper:Signer) => {
  const isPaused = await strat.paused();
  if (isPaused) {
    await strat.connect(keeper).unpause();
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

const wrapNative = async (amount, wNativeAddr, signer) => {
  const wNative = await ethers.getContractAt("IWrappedNative", wNativeAddr, signer);
  await wNative.deposit({ value: amount });
};

export {
  zapNativeToToken,
  swapNativeForToken,
  getVaultWant,
  logTokenBalance,
  unpauseIfPaused,
  getUnirouterData,
};
