import { toFunctionSelector, toFunctionSignature } from "viem";
import fs from "fs";
import path from "node:path";

function readArtifacts(dir, skipDirs) {
  const abis = [];
  const files = fs.readdirSync(dir);

  for (const file of files) {
    if (skipDirs.includes(file)) continue;

    const filePath = path.join(dir, file);
    const stat = fs.statSync(filePath);
    if (stat.isDirectory()) {
      abis.push(...readArtifacts(filePath, skipDirs));
    } else if (stat.isFile() && path.extname(filePath) === ".json") {
      try {
        const fileData = fs.readFileSync(filePath, "utf8");
        const jsonData = JSON.parse(fileData);
        if (jsonData.abi?.length > 0) {
          abis.push({ name: path.parse(filePath).name, abi: jsonData.abi });
        }
      } catch (error) {
        console.error(`Error processing file ${filePath}:`, error.message);
      }
    }
  }

  return abis;
}

function readJsonAbis(dir) {
  const abis = [];
  const files = fs.readdirSync(dir);
  for (const file of files) {
    const filePath = path.join(dir, file);
    try {
      const fileData = fs.readFileSync(filePath, "utf8");
      const abi = JSON.parse(fileData);
      if (abi?.length > 0) {
        abis.push({ name: path.parse(filePath).name, abi });
      }
    } catch (error) {
      console.error(`Error processing file ${filePath}:`, error.message);
    }
  }
  return abis;
}

async function main() {
  const abis = [...readArtifacts("./artifacts", ["build-info"]), ...readJsonAbis("./data/abi")];

  const abiData = {};
  for (const abiFile of abis) {
    for (const abiItem of abiFile.abi) {
      if (["function", "event", "error"].includes(abiItem.type)) {
        const selector = toFunctionSelector(abiItem);
        const signature = toFunctionSignature(abiItem);

        const files = abiData[selector]?.files || [];
        if (!files.includes(abiFile.name)) files.push(abiFile.name);

        const existingSignature = abiData[selector]?.signature;
        if (existingSignature !== undefined && existingSignature !== signature) {
          console.warn(`Same selector "${selector}" for ${signature}, ${existingSignature} in ${files}`);
        }

        abiData[selector] = { signature: signature, abi: abiItem, files };
      }
    }
  }

  fs.mkdirSync("./build", { recursive: true });
  fs.writeFileSync("./build/selectors.json", JSON.stringify(abiData, null, 2));
  fs.copyFileSync(`${__dirname}/index.html`, "./build/index.html");
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
