import { addressBook } from "blockchain-addressbook";
import hardhat from "hardhat";
import getUniswapV3 from "./getUniswapV3";
import getUniswapV2 from "./getUniswapV2";
import getSolidly from "./getSolidly";
import getBalancer from "./getBalancer";

const functionMap: { [key: string]: (swapper: string, params: StepParams) => Promise<StepReturnParams> } = {
  "uniswapV3": getUniswapV3,
  "uniswapV2": getUniswapV2,
  "solidly": getSolidly,
  "balancer": getBalancer,
};

const getSwapper = async (params: SwapperParams): Promise<StepReturnParams[]> => {
  const swapperData: StepReturnParams[] = [];
  const swapper: string = params.swapper ??
    addressBook[hardhat.network.name as keyof typeof addressBook].platforms.beefyfinance.swapper;

  params.steps.forEach(async (step) => {
    swapperData.push(await functionMap[step.stepType](swapper, step))
  });

  return swapperData;
}

export const uint256Max: string = "115792089237316195423570985008687907853269984665640564039457584007913129639935";
export const int256Max: string = "57896044618658097711785492504343953926634992332820282019728792003956564819967";

export interface SwapperParams {
  steps: StepParams[];
  swapper?: string;
}

export interface StepParams {
  stepType: string;
  router: string;
  path: string[];
  fees?: string[];
  stable?: string[];
  poolId?: string[];
}

export interface StepReturnParams {
  target: string;
  value: string;
  data: string;
  tokens: string[];
}

export default getSwapper;
