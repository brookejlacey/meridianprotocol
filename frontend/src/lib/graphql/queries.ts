export const VAULTS_QUERY = `
  query GetVaults {
    vaults(orderBy: "createdAt", orderDirection: "desc") {
      items {
        id
        vaultId
        originator
        status
        totalDeposited
        totalYieldReceived
        totalYieldDistributed
        lastDistribution
        createdAt
        tranches {
          items {
            id
            trancheId
            tokenAddress
            targetApr
            allocationPct
            totalInvested
          }
        }
      }
    }
  }
`;

export const VAULT_DETAIL_QUERY = `
  query GetVault($id: String!) {
    vault(id: $id) {
      id
      vaultId
      originator
      status
      totalDeposited
      totalYieldReceived
      totalYieldDistributed
      lastDistribution
      createdAt
      tranches {
        items {
          id
          trancheId
          tokenAddress
          targetApr
          allocationPct
          totalInvested
        }
      }
    }
    yieldDistributions(where: { vaultId: $id }, orderBy: "timestamp", orderDirection: "desc", limit: 20) {
      items {
        id
        totalYield
        seniorAmount
        mezzAmount
        equityAmount
        timestamp
      }
    }
  }
`;

export const CDS_LIST_QUERY = `
  query GetCDSContracts {
    cdsContracts(orderBy: "createdAt", orderDirection: "desc") {
      items {
        id
        cdsId
        referenceVaultId
        creator
        buyer
        seller
        protectionAmount
        premiumRate
        maturity
        status
        collateralPosted
        totalPremiumPaid
        createdAt
      }
    }
  }
`;

export const USER_INVESTMENTS_QUERY = `
  query GetUserInvestments($investor: String!) {
    investments(where: { investor: $investor }) {
      items {
        id
        vaultId
        trancheId
        investor
        totalInvested
        totalWithdrawn
        totalYieldClaimed
      }
    }
  }
`;

export const MARGIN_ACCOUNT_QUERY = `
  query GetMarginAccount($id: String!) {
    marginAccount(id: $id) {
      id
      user
      openedAt
      collateralPositions {
        items {
          id
          asset
          currentBalance
        }
      }
      liquidations {
        items {
          id
          liquidator
          collateralSeized
          timestamp
        }
      }
    }
  }
`;

export const ASSETS_QUERY = `
  query GetAssets {
    assets {
      items {
        id
        price
        riskWeight
        lastUpdated
      }
    }
  }
`;
