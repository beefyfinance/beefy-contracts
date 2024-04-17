import { ethers } from "hardhat";
import { StepParams, StepReturnParams, uint256Max } from "./getSwapper";
import UniswapV2RouterAbi from "../../../data/abi/UniswapRouterETH.json";

const getUniswapV2 = async (swapper: string, params: StepParams): Promise<StepReturnParams> => {
  const router = await ethers.getContractAt(UniswapV2RouterAbi, params.router);
  const txData = await router.populateTransaction.swapExactTokensForTokens(
    0,
    0,
    params.path,
    swapper,
    uint256Max
  );
  const amountIndex = "4";

  return {
    target: params.router,
    value: "0",
    data: txData.data as string,
    tokens: [params.path[0], amountIndex]
  };
};

export default getUniswapV2;
