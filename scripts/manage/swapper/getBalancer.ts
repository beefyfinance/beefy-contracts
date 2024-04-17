import { ethers } from "hardhat";
import { StepParams, StepReturnParams, uint256Max, int256Max } from "./getSwapper";
import BalancerVaultAbi from "../../../data/abi/BalancerVault.json";

const getBalancer = async (swapper: string, params: StepParams): Promise<StepReturnParams> => {
  const router = await ethers.getContractAt(BalancerVaultAbi, params.router);
  const poolIds: string[] = params.poolId as string[];
  const swapSteps: string[][] = [];
  const funds = [swapper, false, swapper, false];
  const limits = [int256Max];

  poolIds.forEach((poolId, i) => {
    swapSteps.push([poolId, i.toString(), (i + 1).toString(), "0", ]);
    limits.push("0");
  });

  const txData = await router.populateTransaction.batchSwap(
    "0",
    swapSteps,
    params.path,
    funds,
    limits,
    uint256Max
  );
  const amountIndex = 420 + (32 * poolIds.length);

  return {
    target: params.router,
    value: "0",
    data: txData.data as string,
    tokens: [params.path[0], amountIndex.toString()]
  }
};

export default getBalancer;
