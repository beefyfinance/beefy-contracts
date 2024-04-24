import { ethers } from "hardhat";
import { OracleParams, OracleData } from "./oracle";
import UniswapV2FactoryAbi from "../../../data/abi/UniswapV2Factory.json";

const getUniswapV2 = async (params: OracleParams): Promise<OracleData> => {
  const factory = await ethers.getContractAt(UniswapV2FactoryAbi, params.factory as string);
  const path = params.path as string[];
  const tokens = [];
  const pairs = [];
  for (let i = 0; i < path.length - 1; i++) {
    tokens.push(path[i]);
    const pair = await factory.getPair(
      path[i],
      path[i + 1]
    );
    pairs.push(pair);
  }
  tokens.push(path[path.length - 1]);

  const data = ethers.utils.defaultAbiCoder.encode(
    ["address[]","address[]","uint256[]"],
    [tokens, pairs, params.twapPeriods]
  );
  
  return { library: '0xf20935db6A9640481C9ca97A726C467255d9a8bc', data: data };
};

export default getUniswapV2;
