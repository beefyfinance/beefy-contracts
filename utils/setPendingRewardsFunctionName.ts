import { Contract } from "@ethersproject/contracts";

export const setPendingRewardsFunctionName = async (strategy: Contract, pendingRewardsFunctionName: string) => {
    console.log(`Setting pendingRewardsFunctionName to '${pendingRewardsFunctionName}'`)
    await strategy.setPendingRewardsFunctionName(pendingRewardsFunctionName);
}