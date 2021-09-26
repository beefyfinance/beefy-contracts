import hardhat from "hardhat";
import { Contract } from "@ethersproject/contracts";

export const verifyContract = async (
  vault: Contract,
  vaultConstructorArguments: string[],
  strategy: Contract,
  strategyConstructorArguments: string[]
) => {
  await hardhat.run("verify:verify", {
    address: vault.address,
    constructorArguments: vaultConstructorArguments,
  });

  await hardhat.run("verify:verify", {
    address: strategy.address,
    constructorArguments: strategyConstructorArguments,
  });
};
