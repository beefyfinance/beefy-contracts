import type Token from "blockchain-addressbook/types/token";

// Vault configs //
export type CommonConfig = {
    chainId:number;
    platform:string;
    strategist:string;
    unirouter:string,
    outputToNativeRoute:string[];
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