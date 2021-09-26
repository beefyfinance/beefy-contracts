import { Contract } from "@ethersproject/contracts";
import { chainCallFeeMap } from "./chainCallFeeMap";

export const setCorrectCallFee = async (chainName: string, strategy: Contract) => {
  const expectedCallFee = chainCallFeeMap[chainName];
  const defaultCallFee = await strategy.callFee();
  if (expectedCallFee !== defaultCallFee) {
    await strategy.setCallFee(expectedCallFee);
  }
}