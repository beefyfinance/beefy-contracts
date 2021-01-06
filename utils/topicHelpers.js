const Web3 = require("web3");
const BigNumber = require("bignumber.js");

const web3 = new Web3();

const getTopicFromSignature = signature => {
  return web3.utils.keccak256(signature);
};

const getAddressFromTopic = topic => {
  let bytes = web3.utils.hexToBytes(topic);
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[0] == 0) bytes.splice(0, 1);
  }
  return web3.utils.bytesToHex(bytes);
};

const getValueFromData = data => {
  const decoded = web3.eth.abi.decodeParameters(["uint256"], data);
  const value = new BigNumber(decoded["0"]);
  return value;
};

module.exports = { getTopicFromSignature, getAddressFromTopic, getValueFromData };
