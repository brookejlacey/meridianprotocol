# Meridian Frontend

Next.js 16 dApp for interacting with Meridian Protocol on Avalanche Fuji.

## Setup

```bash
npm install
cp .env.example .env.local   # then fill in values
npm run dev                   # http://localhost:3000
```

## Pages

- `/forge` -Structured credit vaults (invest, withdraw, claim yield)
- `/shield` -Bilateral CDS contracts (buy/sell protection, premium payments)
- `/pools` -CDS AMM pools (LP deposit/withdraw, buy protection)
- `/nexus` -Cross-chain margin accounts (collateral management)
- `/strategies` -Yield strategies and auto-compounding
- `/trade` -Secondary market tranche token trading
- `/analytics` -Protocol-wide metrics dashboard

## Stack

Next.js 16, React 19, wagmi 3, viem 2, RainbowKit 2, Tailwind 4, TypeScript 5
