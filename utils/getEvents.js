import hardhat from "hardhat";

export async function getEvents(contract, tx) {
  let receipt = await hardhat.ethers.provider.getTransactionReceipt(tx.hash);
  return receipt.logs.reduce((parsedEvents, log) => {
    try {
      parsedEvents.push(contract.interface.parseLog(log));
    } catch (e) {}
    return parsedEvents;
  }, []);
}

export async function getProxyCreatedAddress(contract, tx) {
  let events = await getEvents(contract, tx);
  let proxyCreatedEvent = events.find(e => e.name === "ProxyCreated");
  return proxyCreatedEvent.args.proxy;
}
