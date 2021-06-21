const hardhatConfig = require("../hardhat.config")

const getNetworkRpc = (network) => {
  return hardhatConfig.networks[network].url
};

module.exports = getNetworkRpc;
