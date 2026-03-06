export const HedgeRouterAbi = [
  {
    "type": "constructor",
    "inputs": [
      {
        "name": "pricer_",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "shieldFactory_",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "createAndHedge",
    "inputs": [
      {
        "name": "p",
        "type": "tuple",
        "internalType": "struct IHedgeRouter.CreateAndHedgeParams",
        "components": [
          {
            "name": "vault",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "trancheId",
            "type": "uint8",
            "internalType": "uint8"
          },
          {
            "name": "investAmount",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "protectionAmount",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "premiumRate",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "maturity",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "oracle",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "paymentInterval",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "maxPremium",
            "type": "uint256",
            "internalType": "uint256"
          }
        ]
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "investAndHedge",
    "inputs": [
      {
        "name": "p",
        "type": "tuple",
        "internalType": "struct IHedgeRouter.InvestAndHedgeParams",
        "components": [
          {
            "name": "vault",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "trancheId",
            "type": "uint8",
            "internalType": "uint8"
          },
          {
            "name": "investAmount",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "cds",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "maxPremium",
            "type": "uint256",
            "internalType": "uint256"
          }
        ]
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "pricer",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract ShieldPricer"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "quoteHedge",
    "inputs": [
      {
        "name": "vault",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "investAmount",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "tenorDays",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "spreadBps",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "estimatedPremium",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "shieldFactory",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract ShieldFactory"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "HedgeCreated",
    "inputs": [
      {
        "name": "user",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "vault",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "trancheId",
        "type": "uint8",
        "indexed": false,
        "internalType": "uint8"
      },
      {
        "name": "investAmount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "cds",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "HedgeExecuted",
    "inputs": [
      {
        "name": "user",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "vault",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "trancheId",
        "type": "uint8",
        "indexed": false,
        "internalType": "uint8"
      },
      {
        "name": "investAmount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "cds",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "ReentrancyGuardReentrantCall",
    "inputs": []
  },
  {
    "type": "error",
    "name": "SafeERC20FailedOperation",
    "inputs": [
      {
        "name": "token",
        "type": "address",
        "internalType": "address"
      }
    ]
  }
] as const;
