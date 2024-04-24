import { ethers } from "hardhat";
import { OracleParams, OracleData } from "./oracle";
import VelodromeFactoryAbi from "../../../data/abi/VelodromeFactory.json";

const getSolidly = async (params: OracleParams): Promise<OracleData> => {
  const factory = await ethers.getContractAt(VelodromeFactoryAbi, params.factory as string);
  const path = params.path as string[];
  const stable = params.stable as string[];
  const tokens = [];
  const pairs = [];
  for (let i = 0; i < path.length - 1; i++) {
    tokens.push(path[i]);
    const pair = await factory["getPool(address,address,bool)"](
      path[i],
      path[i + 1],
      stable[i]
    );
    pairs.push(pair);
  }
  tokens.push(path[path.length - 1]);

  const data = ethers.utils.defaultAbiCoder.encode(
    ["address[]","address[]","uint256[]"],
    [tokens, pairs, params.twapPeriods]
  );
  
  return { library: '0xF5b2701b649691Ea35480E5dbfe0F7E5D8AbA1C1', data: data };
};

export default getSolidly;
