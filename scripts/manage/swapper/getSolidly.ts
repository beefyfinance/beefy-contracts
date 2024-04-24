import { ethers } from "hardhat";
import { StepParams, StepData, uint256Max } from "./swapper";
import VelodromeRouterAbi from "../../../data/abi/VelodromeRouter.json";

const nullAddress: string = "0x0000000000000000000000000000000000000000";

const getSolidly = async (zap: string, params: StepParams): Promise<StepData> => {
  const router = await ethers.getContractAt(VelodromeRouterAbi, params.router);
  const path: string[][] = (params.stable as string[]).map((s, i) => {
    return [params.path[i], params.path[i + 1], s, nullAddress]
  });

  const txData = await router.populateTransaction.swapExactTokensForTokens(0, 0, path, zap, uint256Max);

  return {
    target: params.router,
    value: "0",
    data: txData.data as string,
    tokens: [[params.path[0], "4"]]
  }
};

export default getSolidly;
