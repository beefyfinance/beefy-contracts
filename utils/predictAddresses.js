const rlp = require("rlp");
const keccak = require("keccak");
const Web3 = require("web3");

const predictAddress = async ({ creator, rpc, nonce }) => {
  nonce || await web3.eth.getTransactionCount(creator);
  
  const web3 = new Web3(rpc);

  const nonceHex = `0x${parseInt(nonce).toString(16)}`;
  const rlpEncoded = rlp.encode([creator, nonceHex]);
  const contractAddressLong = keccak("keccak256").update(rlpEncoded).digest("hex");
  const address = `0x${contractAddressLong.substring(24)}`;
  const checksumed = web3.utils.toChecksumAddress(address);

  return checksumed;
};

const predictAddresses = async ({ creator, rpc }) => {
  creator = creator || "0x565EB5e5B21F97AE9200D121e77d2760FFf106cb";
  rpc = rpc || "https://bsc-dataseed.binance.org/";

  const nonce = await web3.eth.getTransactionCount(creator);

  return {
    vault: await predictAddress({creator,rpc, nonce}),
    strategy: await predictAddress({creator,rpc, nonce: (nonce + 1)}),
  };
};

module.exports = { predictAddresses, predictAddress };
