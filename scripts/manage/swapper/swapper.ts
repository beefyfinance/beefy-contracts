import hardhat, { ethers } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import swapperAbi from "../../../artifacts/contracts/BIFI/infra/BeefySwapper.sol/BeefySwapper.json";
import strategyAbi from "../../../artifacts/contracts/BIFI/strategies/Common/BaseStrategy.sol/BaseStrategy.json";
import { checkOracle } from "../oracle/oracle";

import getUniswapV3 from "./getUniswapV3";
import getUniswapV2 from "./getUniswapV2";
import getSolidly from "./getSolidly";
import getBalancer from "./getBalancer";

const swapper = "0x4e8ddA5727c62666Bc9Ac46a6113C7244AE9dbdf";
const zap = "0x6F19Da51d488926C007B9eBaa5968291a2eC6a63";

const functionMap: { [key: string]: (zap: string, params: StepParams) => Promise<StepData> } = {
  "uniswapV3": getUniswapV3,
  "uniswapV2": getUniswapV2,
  "solidly": getSolidly,
  "balancer": getBalancer,
};

export const setSwapper = async (strategy: string, params: SwapperParams[]) => {
  const fromTokens: string[] = [];
  const toTokens: string[] = [];
  const datas: StepData[][] = [];

  await Promise.all(params.map(async (s) => {
    const [ routeExists, fromOracleFound, toOracleFound ] = await Promise.all([
      checkSwapper(strategy, s),
      checkOracle(strategy, s.from),
      checkOracle(strategy, s.to)
    ]);

    if (routeExists) {
      console.log(`Route ${s.from} to ${s.to} already exists`);
      return;
    }
    if (!fromOracleFound) {
      console.log(`Oracle not found for ${s.from}, route from ${s.from} to ${s.to} failed`);
      return;
    }
    if (!toOracleFound) {
      console.log(`Oracle not found for ${s.to}, route from ${s.from} to ${s.to} failed`);
      return;
    }

    const data = await getSwapper(s);
    fromTokens.push(s.from);
    toTokens.push(s.to);
    datas.push(data);
  }));

  if (datas.length === 0) {
    console.log("No routes were set");
    return;
  }

  const strategyContract = await ethers.getContractAt(strategyAbi.abi, strategy);
  let routingTx = await strategyContract.setSwapSteps(fromTokens, toTokens, datas);
  routingTx = await routingTx.wait()
  routingTx.status === 1
  ? console.log(`Routing set for ${fromTokens} to ${toTokens} with tx: ${routingTx.transactionHash}`)
  : console.log(`Routing failed with tx: ${routingTx.transactionHash}`);
}

const getSwapper = async (params: SwapperParams): Promise<StepData[]> => {
  const swapperData: StepData[] = [];
  await Promise.all(params.steps.map(async (step) => {
    swapperData.push(await functionMap[step.stepType](zap, step))
  }));

  return swapperData;
}

const checkSwapper = async (strategy: string, params: SwapperParams): Promise<boolean> => {
  const swapperContract = await ethers.getContractAt(swapperAbi.abi, swapper);
  let [ routingTx ] = await Promise.all([swapperContract.getSwapSteps(strategy, params.from, params.to)]);
  return routingTx.length > 0;
}

export const uint256Max: string = "115792089237316195423570985008687907853269984665640564039457584007913129639935";
export const int256Max: string = "57896044618658097711785492504343953926634992332820282019728792003956564819967";

export interface StepParams {
  stepType: string;
  router: string;
  path: string[];
  stable?: string[];
  fees?: string[];
  poolId?: string[];
}

export interface SwapperParams {
  from: string;
  to: string;
  steps: StepParams[];
}

export interface StepData {
  target: string;
  value: string;
  data: string;
  tokens: string[][];
}
