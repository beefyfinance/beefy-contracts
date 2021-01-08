const getNetworkRpc = network => {
  if (network === "mainnet") {
    return process.env.BSC_RPC;
  } else if (network === "testnet")
    return "https://data-seed-prebsc-1-s1.binance.org:8545/";
  else {
    return "http://127.0.0.1:8545";
  }
};

module.exports = getNetworkRpc;
