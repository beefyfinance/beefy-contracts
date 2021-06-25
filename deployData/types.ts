import { Overrides } from "@ethersproject/contracts";
import { ChainId } from "blockchain-addressbook/types/chainid";
import type Token from "blockchain-addressbook/types/token";
import { BeefyVaultV6__factory, StrategyCommonChefLP__factory, StrategyCommonRewardPoolLP__factory } from "../typechain";

// NOTE:
// It is important that you do net use arrow function notation to add methods to these classes.
// They will not be properly inherited.

type NonFunctionPropertyNames<T> = {
    [K in keyof T]: T[K] extends Function ? never : K;
}[keyof T];
type NonFunctionProperties<T> = Pick<T, NonFunctionPropertyNames<T>>;

type SwapRoute = [Token, ...Token[]];

export function VaultConfig
    <TConfig extends BaseConfig>
    (tConfig: new () => TConfig, config: NonFunctionProperties<TConfig>) {
        if (Reflect.setPrototypeOf(config,tConfig.prototype))
            return config as TConfig;
        throw "error";
    }

export abstract class BaseConfig {
    readonly chainId: ChainId;
    readonly platform: string;
    readonly strategist: string;
    readonly unirouter: string;
    readonly outputToNativeRoute: SwapRoute;
    readonly withdrawalFee?: number;
    readonly strategy?: string;

    abstract getWantAddress(): string;
    abstract getWantSymbol(): string;

    getMooName() {return `Moo ${this.platform} ${this.getWantSymbol()}`};
    getMooSymbol() {return `moo${this.platform}${this.getWantSymbol()}`};

    getVaultContract() {return 'BeefyVaultV6'};
    getVaultParams(strat: string, overrides?: Overrides):Parameters<BeefyVaultV6__factory['deploy']> {
        return [
            strat,
            this.getMooName(),
            this.getMooSymbol(),
            21600,
        ];
    };

    abstract getStratContract():string;
    abstract getStratParams(vault: string, keeper: string, beefyFeeRecipient: string, overrides?: Overrides):any[];
}

// Want configs //
abstract class LpConfig extends BaseConfig {
    readonly want: string;
    readonly outputToLp0Route: SwapRoute;
    readonly outputToLp1Route: SwapRoute;

    getWantAddress() { return this.want };
    getWantSymbol() { return `${this.outputToLp0Route[this.outputToLp0Route.length-1].symbol}-${this.outputToLp1Route[this.outputToLp1Route.length-1].symbol}` };
};

abstract class SingleConfig extends BaseConfig {
    readonly token: Token;
    readonly outputToWantRoute: SwapRoute;

    getWantAddress() { return this.token.address };
    getWantSymbol() { return this.token.symbol; };
};

// Strat configs //
export class StrategyCommonRewardPoolLPConfig extends LpConfig {
    readonly rewardPool: string;

    getStratContract() {return 'StrategyCommonRewardPoolLP'};
    getStratParams(vault: string, keeper: string, beefyFeeRecipient: string, overrides?: Overrides):Parameters<StrategyCommonRewardPoolLP__factory['deploy']> {
        return [
            this.want,
            this.rewardPool,
            vault,
            this.unirouter,
            keeper,
            this.strategist,
            beefyFeeRecipient,
            this.outputToNativeRoute.map(t => t.address),
            this.outputToLp0Route.map(t => t.address),
            this.outputToLp1Route.map(t => t.address)
        ]
    }
}

export class StrategyCommonChefLPConfig extends LpConfig {
    readonly chef:string;
    readonly poolId:number;

    getStratContract() {return 'StrategyCommonChefLP'};
    getStratParams(vault: string, keeper: string, beefyFeeRecipient: string, overrides?: Overrides):Parameters<StrategyCommonChefLP__factory['deploy']> {
        return [
            this.want,
            this.poolId,
            this.chef,
            vault,
            this.unirouter,
            keeper,
            this.strategist,
            beefyFeeRecipient,
            this.outputToNativeRoute.map(t => t.address),
            this.outputToLp0Route.map(t => t.address),
            this.outputToLp1Route.map(t => t.address)
        ]
    }
}
