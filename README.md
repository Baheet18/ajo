# Ajo

A rotating savings group (ajo / esusu) app built on Arc, where USDC is the native gas token. Groups of 2–10 people pool contributions each round; the pot goes to the next person in the payout order until everyone has received once.

Built with [Arc Studio](https://studio.arc.io)

## What it does

- Create a savings circle with a name, contribution size, number of members, and round length.
- Choose a trust level (Friends / Mixed / Strangers) that controls how much holdback is withheld from early payouts as assurance.
- Members join a pending circle and optionally lock a security deposit.
- Creator can set a custom payout order while the circle is still pending.
- Each round: everyone contributes, the pot pays out to the next person in the sequence.
- Non-paying members are slashed (holdback first, then deposit). Both exhausted means permanent exclusion.
- Members can leave a pending circle and recover their deposit. Pending circles expire after 7 days and any member can cancel.

## Tech Stack

- React 18, Vite, TypeScript, Tailwind CSS, Bun
- wagmi v2, viem v2, Privy (email + Google + external wallet sign-in, embedded wallets)
- Solidity ^0.8.20, Foundry (82 tests)
- Arc Mainnet (Chain ID 5042), USDC as native gas

## Prerequisites

- Bun 1.x
- Node 18+
- Foundry (for contract work)

## Install

```bash
bun install
```

## Environment Variables

| Variable | Purpose |
|---|---|
| `VITE_AJO_ADDRESS` | Deployed `AjoCircle` contract address on Arc Mainnet. Must be set before building for production. |
| `VITE_PRIVY_APP_ID` | Privy app ID. Defaults to a dev fallback; set your own for production and add your domain to the Privy allowed-origins list. |
| `VITE_PUBLIC_URL` | Optional. Base URL for invite links. When empty, uses the current site's origin. |

## Run (development)

```bash
bun run dev
```

## Build (production)

Set `VITE_AJO_ADDRESS` to the deployed mainnet contract address in `.env`, then:

```bash
bun run build
```

## Test contracts

```bash
forge test
```

## Check (lint + types)

```bash
bun run check
```

## Deployment

The flattened contract source for manual deployment and block-explorer verification is at `docs/AjoCircle_flat.sol`.

Exact compiler settings required for verification:
- solc `0.8.28`
- Optimizer: enabled, 200 runs
- EVM version: `paris`
- Via IR: `true`
