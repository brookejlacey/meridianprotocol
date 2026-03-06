export const ForgeFactoryAbi = [
  {
    "type": "function",
    "name": "createVault",
    "inputs": [
      {
        "name": "params",
        "type": "tuple",
        "internalType": "struct ForgeFactory.CreateVaultParams",
        "components": [
          {
            "name": "underlyingAsset",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "trancheTokenAddresses",
            "type": "address[3]",
            "internalType": "address[3]"
          },
          {
            "name": "trancheParams",
            "type": "tuple[3]",
            "internalType": "struct IForgeVault.TrancheParams[3]",
            "components": [
              {
                "name": "targetApr",
                "type": "uint256",
                "internalType": "uint256"
              },
              {
                "name": "allocationPct",
                "type": "uint256",
                "internalType": "uint256"
              },
              {
                "name": "token",
                "type": "address",
                "internalType": "address"
              }
            ]
          },
          {
            "name": "distributionInterval",
            "type": "uint256",
            "internalType": "uint256"
          }
        ]
      }
    ],
    "outputs": [
      {
        "name": "vaultAddress",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "getOriginatorVaults",
    "inputs": [
      {
        "name": "originator_",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256[]",
        "internalType": "uint256[]"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getVault",
    "inputs": [
      {
        "name": "vaultId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "vaultCount",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "vaults",
    "inputs": [
      {
        "name": "id",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "vault",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "vaultsByOriginator",
    "inputs": [
      {
        "name": "originator",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "vaultIds",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "VaultCreated",
    "inputs": [
      {
        "name": "vaultId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "vault",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "originator",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "underlyingAsset",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      }
    ],
    "anonymous": false
  }
] as const;
