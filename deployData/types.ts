import { ChainId } from "blockchain-addressbook/types/chainid";
import type Token from "blockchain-addressbook/types/token";

// Vault configs //
export type CommonConfig = {
    chainId:ChainId;
    platform:string;
    strategist:string;
    unirouter:string,
    outputToNativeRoute:string[];
    withdrawalFee?:number
};

// Strat configs //
export type RewardPoolConfig = {
    rewardPool:string,
};

export type ChefConfig = {
    chef:string,
    poolId:number
};

// Want configs //
export type LpConfig = {
    want:string,
    lp0:Token,
    lp1:Token,
    outputToLp0Route:string[],
    outputToLp1Route:string[],
};

export type SingleConfig = {
    want:Token,
    outputToWantRoute:string[],
};