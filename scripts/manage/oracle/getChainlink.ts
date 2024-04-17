import hardhat, { ethers } from "hardhat";
import { OracleParams, OracleReturnParams } from "./getOracle";
import { addressBook } from "blockchain-addressbook";

const chainlinkOracleLib: string = 
  addressBook[hardhat.network.name as keyof typeof addressBook].platforms.beefyfinance.strategyOwner;

const getChainlink = async (params: OracleParams): Promise<OracleReturnParams> => {
  const data = ethers.utils.defaultAbiCoder.encode(
    ["address"],
    [params.feed]
  );

  return { library: chainlinkOracleLib, data: data };
};

export default getChainlink;
