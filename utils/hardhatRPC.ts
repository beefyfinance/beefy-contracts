import { EthereumProvider } from "hardhat/types";

async function increaseTime(provider:EthereumProvider, seconds:number) {
    return await provider.request({ method: "evm_increaseTime", params: [seconds] });
}

async function setNextBlockTimestamp(provider:EthereumProvider, timestamp:number) {
    return await provider.request({ method: "evm_setNextBlockTimestamp", params: [timestamp] });
}

enum BlockTag {
    Earliest = "earliest",
    Latest = "latest",
    Pending = "pending"
}

async function getBlockByNumber(provider:EthereumProvider, block:number|BlockTag, full:boolean) {
    return await provider.send("eth_getBlockByNumber", [block, full]);
}

export default {
    BlockTag,
    increaseTime,
    setNextBlockTimestamp,
    getBlockByNumber
}