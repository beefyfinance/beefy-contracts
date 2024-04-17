import getChainlink from "./getChainlink";
import getPyth from "./getPyth";
import getUniswapV3 from "./getUniswapV3";
import getUniswapV2 from "./getUniswapV2";
import getSolidly from "./getSolidly";

const functionMap: { [key: string]: (params: OracleParams) => Promise<any> } = {
  "chainlink": getChainlink,
  "pyth": getPyth,
  "uniswapV3": getUniswapV3,
  "uniswapV2": getUniswapV2,
  "solidly": getSolidly,
};

const getOracle = async (params: OracleParams): Promise<OracleReturnParams> => {
  const oracleType: string = params.oracleType;
  return functionMap[oracleType](params);
}

export interface OracleParams {
  oracleType: string;
  feed?: string;
  factory?: string;
  path?: string[];
  fees?: number[];
  twapPeriods?: string[];
  priceId?: string;
}

export interface OracleReturnParams {
  library: string;
  data: string;
}

export default getOracle;
