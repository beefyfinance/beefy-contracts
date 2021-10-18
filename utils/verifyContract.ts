import hardhat from "hardhat";
import { Contract } from "@ethersproject/contracts";

export const verifyContract = async (
  contract: Contract,
  constructorArguments: any[],
) => {
  await hardhat.run("verify:verify", {
    address: contract.address,
    constructorArguments,
  });
};
