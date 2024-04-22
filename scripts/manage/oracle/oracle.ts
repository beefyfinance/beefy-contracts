import { ethers } from "hardhat";
import strategyAbi from "../../../artifacts/contracts/BIFI/strategies/Common/StrategySwapper.sol/StrategySwapper.json";
import oracleAbi from "../../../artifacts/contracts/BIFI/infra/BeefyOracle/BeefyOracle.sol/BeefyOracle.json";

import getChainlink from "./getChainlink";
import getPyth from "./getPyth";
import getUniswapV3 from "./getUniswapV3";
import getUniswapV2 from "./getUniswapV2";
import getSolidly from "./getSolidly";

const oracle = "0x1BfA205114678c7d17b97DB7A71819D3E6718eb4";

const functionMap: { [key: string]: (params: OracleParams) => Promise<any> } = {
  "chainlink": getChainlink,
  "pyth": getPyth,
  "uniswapV3": getUniswapV3,
  "uniswapV2": getUniswapV2,
  "solidly": getSolidly,
};

export const setOracle = async (strategy: string, params: OracleParams[]) => {
  const tokens: string[] = [];
  const libraries: string[] = [];
  const datas: string[] = [];

  await Promise.all(params.map(async (o) => {
    if (await checkOracle(strategy, o.token)) {
      console.log(`Existing oracle found for ${o.token}`);
    } else {
      const data = await getOracle(o);
      tokens.push(o.token);
      libraries.push(data.library);
      datas.push(data.data);
    }
  }));

  if (datas.length === 0) {
    console.log("No oracles were set");
    return;
  }

  const strategyContract = await ethers.getContractAt(strategyAbi.abi, strategy);
  let routingTx = await strategyContract.setOracles(tokens, libraries, datas);
  routingTx = await routingTx.wait()
  routingTx.status === 1
  ? console.log(`Oracles set for ${tokens}`)
  : console.log(`Oracles failed for ${tokens}`);
}

const getOracle = async (params: OracleParams): Promise<OracleData> => {
  const oracleType: string = params.oracleType;
  return functionMap[oracleType](params);
}

export const checkOracle = async (strategy: string, token: string): Promise<boolean> => {
  const oracleContract = await ethers.getContractAt(oracleAbi.abi, oracle);
  let [ oraclePrice ] = await Promise.all([oracleContract["getPrice(address,address)"](strategy, token)]);
  return oraclePrice > 0;
}

export interface OracleParams {
  token: string;
  oracleType: string;
  feed?: string;
  factory?: string;
  path?: string[];
  fees?: number[];
  twapPeriods?: string[];
  priceId?: string;
}

export interface OracleData {
  library: string;
  data: string;
}
