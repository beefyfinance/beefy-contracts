import { ChainId } from "blockchain-addressbook"

export const chainCallFeeMap: Record<keyof typeof ChainId & "localhost", number> = {
    bsc: 111,
    avax: 111,
    polygon: 11,
    heco: 11,
    fantom: 11,
    one: 111,
    arbitrum: 111,

    localhost: 11,
  }