const fs = require("fs");

function getContractPath(contractName) {
  // Recursively search for contract file
  function findContractFile(dir, contractName) {
    const files = fs.readdirSync(dir);
    for (const file of files) {
      const path = `${dir}/${file}`;
      const stat = fs.statSync(path);
      if (stat.isDirectory()) {
        const found = findContractFile(path, contractName);
        if (found) return found;
      } else if (file.includes(contractName)) {
        return path;
      }
    }
    return null;
  }

  const contractPath = findContractFile("contracts", contractName);
  if (!contractPath) {
    throw new Error(`Contract ${contractName} not found`);
  }
  return contractPath;
}

function getVerifyCommand(network, contractName, address, params) {
  try {
    const contractPath = getContractPath(contractName);
    const paramsString = params ? params.map(param => `"${param}"`).join(" ") : "";
    return `npx hardhat verify --network ${network} ${contractPath}:${contractName} ${address} ${paramsString}`;
  } catch (error) {
    console.error(`Error getting verify command for ${contractName}:`, error);
    return null;
  }
}

module.exports = {
  getContractPath,
  getVerifyCommand,
};
