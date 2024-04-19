import { ethers } from "hardhat";
import { OracleParams, OracleData } from "./oracle";

const getChainlink = async (params: OracleParams): Promise<OracleData> => {
  const data = ethers.utils.defaultAbiCoder.encode(
    ["address"],
    [params.feed]
  );

  return { library: '0xf35D758fd1a21168F09e674a67DFEA8c9860545B', data: data };
};

export default getChainlink;
