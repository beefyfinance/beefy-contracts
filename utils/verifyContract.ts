import hardhat from "hardhat";
import { Contract } from "@ethersproject/contracts";

export const verifyContract = async (address: string, constructorArguments: any[]) => {
  await hardhat.run("verify:verify", {
    address,
    constructorArguments,
  });
};
