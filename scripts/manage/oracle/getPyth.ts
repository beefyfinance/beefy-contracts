import { ethers } from "hardhat";
import { OracleParams, OracleData } from "./oracle";

const getPyth = async (params: OracleParams): Promise<OracleData> => {
  const data = ethers.utils.defaultAbiCoder.encode(
    ["address", "bytes32"],
    [params.feed, params.priceId]
  );

  return { library: '',/*pythOracleLib*/ data: data };
};

export default getPyth;
