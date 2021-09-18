import dotenv from "dotenv";
dotenv.config();
import { HardhatNetworkAccountUserConfig } from "hardhat/src/types/config";

export const getPKs = () => {
  let deployerAccount, keeperAccount, upgraderAccount, rewarderAccount;

  // PKs without `0x` prefix
  if (process.env.DEPLOYER_PK) deployerAccount = process.env.DEPLOYER_PK;
  if (process.env.KEEPER_PK) keeperAccount = process.env.KEEPER_PK;
  if (process.env.UPGRADER_PK) upgraderAccount = process.env.UPGRADER_PK;
  if (process.env.REWARDER_PK) rewarderAccount = process.env.REWARDER_PK;

  const accounts = [deployerAccount, keeperAccount, upgraderAccount, rewarderAccount].filter(pk => !!pk);
  return accounts;
};

export const buildHardhatNetworkAccounts = accounts => {
  const hardhatAccounts = accounts.map(pk => {
    // hardhat network wants 0x prefix in front of PK
    const accountConfig: HardhatNetworkAccountUserConfig = {
      privateKey: pk,
      balance: "1000000000000000000000000",
    };
    return accountConfig;
  });
  return hardhatAccounts;
};
