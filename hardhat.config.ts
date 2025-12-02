import fs from "fs";
import type { HardhatUserConfig } from "hardhat/config";

import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable } from "hardhat/config";

const ENV_FILE = ".env";

if (fs.existsSync(ENV_FILE))
  process.loadEnvFile(ENV_FILE);

const config: HardhatUserConfig = {
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    profiles: {
      default: {
        version: "0.8.30",
        settings: {
          viaIR: true,
        }
      },
      production: {
        version: "0.8.30",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 800,
          },
        },
      },
    },
  },
  test: {
    solidity: {
      allowInternalExpectRevert: true,
      fuzz: {
        runs: Number(process.env.FUZZ_RUNS) || 1024,
      },
      fsPermissions: {
        readDirectory: ["node_modules/@uniswap"]
      },
    },
  },
  networks: {
    hardhatMainnet: {
      type: "edr-simulated",
      chainType: "l1",
    },
    hardhatOp: {
      type: "edr-simulated",
      chainType: "op",
    },
    sepolia: {
      type: "http",
      chainType: "l1",
      url: configVariable("SEPOLIA_RPC_URL"),
      accounts: [configVariable("SEPOLIA_PRIVATE_KEY")],
    },
  },
};

export default config;
