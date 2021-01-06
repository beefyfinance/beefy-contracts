const rlp = require("rlp");
const keccak = require("keccak");
const Web3 = require("web3");

const predictAddresses = async (config) => {
  let { creator, rpc } = config;

  creator = creator || "0x565EB5e5B21F97AE9200D121e77d2760FFf106cb";
  rpc = rpc || "https://bsc-dataseed.binance.org/";

  const web3 = new Web3(rpc);

  let currentNonce = await web3.eth.getTransactionCount(creator);
  let currentNonceHex = `0x${parseInt(currentNonce).toString(16)}`;
  let currentInputArr = [creator, currentNonceHex];
  let currentRlpEncoded = rlp.encode(currentInputArr);
  let currentContractAddressLong = keccak("keccak256").update(currentRlpEncoded).digest("hex");
  let currentContractAddress = `0x${currentContractAddressLong.substring(24)}`;
  let currentContractAddressChecksum = web3.utils.toChecksumAddress(currentContractAddress);

  let nextNonce = currentNonce + 1;
  let nextNonceHex = `0x${parseInt(nextNonce).toString(16)}`;
  let nextInputArr = [creator, nextNonceHex];
  let nextRlpEncoded = rlp.encode(nextInputArr);
  let nextContractAddressLong = keccak("keccak256").update(nextRlpEncoded).digest("hex");
  let nextContractAddress = `0x${nextContractAddressLong.substring(24)}`;
  let nextContractAddressChecksum = web3.utils.toChecksumAddress(nextContractAddress);

  return {
    vault: currentContractAddressChecksum,
    strategy: nextContractAddressChecksum,
  };
};

module.exports = predictAddresses;
