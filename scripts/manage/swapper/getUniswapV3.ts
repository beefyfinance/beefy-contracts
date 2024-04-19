import { ethers } from "hardhat";
import { StepParams, StepData, uint256Max } from "./swapper";
import UniswapV3RouterAbi from "../../../data/abi/UniswapV3Router.json";

const getUniswapV3 = async (swapper: string, params: StepParams): Promise<StepData> => {
  const router = await ethers.getContractAt(UniswapV3RouterAbi, params.router);
  const fees = params.fees as string[];

  let path = ethers.utils.solidityPack(
    ["address"],
    [params.path[0]]
  );
  for (let i = 0; i < params.path.length - 1; i++) {
    path = ethers.utils.solidityPack(
      ["bytes", "uint24", "address"],
      [path, fees[i], params.path[i + 1]]
    );
  }
  const exactInputParams = [path, swapper, uint256Max, 0, 0];
  const txData = await router.populateTransaction.exactInput(exactInputParams);
  const amountIndex = "132";

  return {
    target: params.router,
    value: "0",
    data: txData.data as string,
    tokens: [[params.path[0], amountIndex]]
  }
};

export default getUniswapV3;
