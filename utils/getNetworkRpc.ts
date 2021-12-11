import { HttpNetworkUserConfig } from "hardhat/src/types/config";
import hardhatConfig from "../hardhat.config";

export const getNetworkRpc = (network: keyof typeof hardhatConfig.networks) => {
  const networkConfig = hardhatConfig.networks![network] as HttpNetworkUserConfig
  return networkConfig.url;
};