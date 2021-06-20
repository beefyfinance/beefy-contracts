import { ChainId } from "blockchain-addressbook/types/chainid";

type ChainSettings = {
    callFee:number
}

const chainSettings:Record<ChainId,ChainSettings> = {
    [ChainId.avax]: {
        callFee:11,
    },
    [ChainId.bsc]: {
        callFee:111,
    },
    [ChainId.fantom]: {
        callFee:11,
    },
    [ChainId.heco]: {
        callFee:11,
    },
    [ChainId.polygon]: {
        callFee:11,
    },
};

export default chainSettings;