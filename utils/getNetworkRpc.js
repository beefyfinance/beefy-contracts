const getNetworkRpc = network => {
  if (network === "mainnet") {
    return process.env.BSC_RPC;
  } else {
    return "http://127.0.0.1:8545";
  }
};

module.exports = getNetworkRpc;
