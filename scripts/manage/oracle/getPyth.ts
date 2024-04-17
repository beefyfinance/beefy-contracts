import hardhat, { ethers } from "hardhat";
import { OracleParams, OracleReturnParams } from "./getOracle";
import { addressBook } from "blockchain-addressbook";

const pythOracleLib: string = 
  addressBook[hardhat.network.name as keyof typeof addressBook].platforms.beefyfinance.strategyOwner;

const getPyth = async (params: OracleParams): Promise<OracleReturnParams> => {
  const data = ethers.utils.defaultAbiCoder.encode(
    ["address", "bytes32"],
    [params.feed, params.priceId]
  );

  return { library: pythOracleLib, data: data };
};

export default getPyth;
