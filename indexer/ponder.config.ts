import { createConfig, factory } from "ponder";
import { parseAbiItem } from "viem";

import { ForgeFactoryAbi } from "./abis/ForgeFactory";
import { ForgeVaultAbi } from "./abis/ForgeVault";
import { ShieldFactoryAbi } from "./abis/ShieldFactory";
import { CDSContractAbi } from "./abis/CDSContract";
import { CDSPoolFactoryAbi } from "./abis/CDSPoolFactory";
import { CDSPoolAbi } from "./abis/CDSPool";
import { NexusHubAbi } from "./abis/NexusHub";
import { CreditEventOracleAbi } from "./abis/CreditEventOracle";
import { CollateralOracleAbi } from "./abis/CollateralOracle";

const START_BLOCK = 51648911;

export default createConfig({
  chains: {
    fuji: {
      id: 43113,
      rpc: process.env.PONDER_RPC_URL_43113,
    },
  },
  contracts: {
    // --- Static contracts (known addresses) ---
    ForgeFactory: {
      abi: ForgeFactoryAbi,
      chain: "fuji",
      address: "0x52614038F825FbA5BE78ECf3eA0e3e0b21961d29",
      startBlock: START_BLOCK,
    },
    ShieldFactory: {
      abi: ShieldFactoryAbi,
      chain: "fuji",
      address: "0x9A9e51c6A91573dEFf7657baB7570EF4888Aaa3A",
      startBlock: START_BLOCK,
    },
    NexusHub: {
      abi: NexusHubAbi,
      chain: "fuji",
      address: "0xE6bb9535bd754A993dc04E83279f92980F7ad9F4",
      startBlock: START_BLOCK,
    },
    CreditEventOracle: {
      abi: CreditEventOracleAbi,
      chain: "fuji",
      address: "0x8E28b5C0fc6053F70dB768Fa9F35a3a8a3f35175",
      startBlock: START_BLOCK,
    },
    CollateralOracle: {
      abi: CollateralOracleAbi,
      chain: "fuji",
      address: "0x6323948435A6CF7553fB69840EdD07f1ab248eb3",
      startBlock: START_BLOCK,
    },

    // --- Dynamic contracts (factory-created) ---
    ForgeVault: {
      abi: ForgeVaultAbi,
      chain: "fuji",
      address: factory({
        address: "0x52614038F825FbA5BE78ECf3eA0e3e0b21961d29",
        event: parseAbiItem(
          "event VaultCreated(uint256 indexed vaultId, address indexed vault, address indexed originator, address underlyingAsset)"
        ),
        parameter: "vault",
      }),
      startBlock: START_BLOCK,
    },
    CDSContract: {
      abi: CDSContractAbi,
      chain: "fuji",
      address: factory({
        address: "0x9A9e51c6A91573dEFf7657baB7570EF4888Aaa3A",
        event: parseAbiItem(
          "event CDSCreated(uint256 indexed cdsId, address indexed cds, address indexed referenceAsset, address creator, uint256 protectionAmount, uint256 premiumRate, uint256 maturity)"
        ),
        parameter: "cds",
      }),
      startBlock: START_BLOCK,
    },

    // --- CDS Pool AMM ---
    CDSPoolFactory: {
      abi: CDSPoolFactoryAbi,
      chain: "fuji",
      address: "0xEc82dd21231dAcbA07f1C4F06B84Cf7bc6b4C24c",
      startBlock: START_BLOCK,
    },
    CDSPool: {
      abi: CDSPoolAbi,
      chain: "fuji",
      address: factory({
        address: "0xEc82dd21231dAcbA07f1C4F06B84Cf7bc6b4C24c",
        event: parseAbiItem(
          "event PoolCreated(uint256 indexed poolId, address indexed pool, address indexed referenceAsset, address creator, uint256 baseSpreadWad, uint256 slopeWad, uint256 maturity)"
        ),
        parameter: "pool",
      }),
      startBlock: START_BLOCK,
    },
  },
});
