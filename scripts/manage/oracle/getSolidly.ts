import { ethers } from "hardhat";
import { OracleParams, OracleData } from "./oracle";
import VelodromeFactoryAbi from "../../../data/abi/VelodromeFactory.json";

const getSolidly = async (params: OracleParams): Promise<OracleData> => {
  const factory = await ethers.getContractAt(VelodromeFactoryAbi, params.factory as string);
  const path = params.path as string[];
  const tokens = [];
  const pairs = [];
  for (let i = 0; i < path.length; i++) {
    tokens.push(path[i][0]);
    const pair = await factory.getPair(
      path[i][0],
      path[i][1],
      path[i][2]
    );
    pairs.push(pair);
  }
  tokens.push(path[path.length - 1][1]);

  const data = ethers.utils.defaultAbiCoder.encode(
    ["address[]","address[]","uint256[]"],
    [tokens, pairs, params.twapPeriods]
  );
  
  return { library: ''/*solidlyOracleLib*/, data: data };
};

export default getSolidly;
