import hardhat, { ethers } from "hardhat";
import { OracleParams, OracleReturnParams } from "./getOracle";
import { addressBook } from "blockchain-addressbook";
import UniswapV3FactoryAbi from "../../../data/abi/UniswapV3Factory.json";

const uniswapV3OracleLib: string = 
  addressBook[hardhat.network.name as keyof typeof addressBook].platforms.beefyfinance.strategyOwner;

const getUniswapV3 = async (params: OracleParams): Promise<OracleReturnParams> => {
  const factory = await ethers.getContractAt(UniswapV3FactoryAbi, params.factory as string);
  const path = params.path as string[];
  const fees = params.fees as number[];
  const tokens = [];
  const pairs = [];
  for (let i = 0; i < path.length; i++) {
    tokens.push(path[i][0]);
    const pair = await factory.getPool(
      path[i][0],
      path[i][1],
      fees[i],
    );
    pairs.push(pair);
  }
  tokens.push(path[path.length - 1][1]);

  const data = ethers.utils.defaultAbiCoder.encode(
    ["address[]","address[]","uint256[]"],
    [tokens, pairs, params.twapPeriods]
  );

  return { library: uniswapV3OracleLib, data: data };
};

export default getUniswapV3;
