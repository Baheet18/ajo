# Ajo — Rotating Savings Group on Arc

> Built with Arc Studio — money-powered apps in minutes

A rotating savings group (ajo/esusu) dapp where groups of 2–10 members save together in USDC. Everyone contributes each round; the pot goes to the next person in the payout order.

---

## Deployed Contracts

| Contract | Chain | Address | Explorer |
|---|---|---|---|
| AjoCircle v1 (deprecated) | Arc Testnet | `0xdcef975947fc86f344164dab25af4aaaceb9f0ca` | [View](https://explorer.testnet.arc.io/address/0xdcef975947fc86f344164dab25af4aaaceb9f0ca) |
| AjoCircle v2 (deprecated) | Arc Testnet | `0xd78cd3378823ed3963a95ea4f9d88352001b8b62` | [View](https://explorer.testnet.arc.io/address/0xd78cd3378823ed3963a95ea4f9d88352001b8b62) |
| AjoCircle v3 (deprecated) | Arc Testnet | `0xf4a21b74f442f9672a1787fed6ebfcdfb73cd8a2` | [View](https://explorer.testnet.arc.io/address/0xf4a21b74f442f9672a1787fed6ebfcdfb73cd8a2) |
| AjoCircle v4 (deprecated) | Arc Testnet | `0x1db5c7c8f2ab1bb84674024e952a151240e136ab` | [View](https://explorer.testnet.arc.io/address/0x1db5c7c8f2ab1bb84674024e952a151240e136ab) |
| AjoCircle v5 (Fix 6: holdbackBps, reputation, trust levels) | Arc Testnet | `0x64822c48a4de920e74d16df88cb3b0b6924819d6` | [View](https://explorer.testnet.arc.io/address/0x64822c48a4de920e74d16df88cb3b0b6924819d6) |

## Tech Stack

- Frontend: React 18, Vite, TypeScript, Tailwind CSS
- Web3: wagmi v2, viem v2, ConnectKit
- Contracts: Solidity 0.8.28 + Foundry. Sources in `contracts/`, unit tests in `contracts/test/` (50/50 pass).
- Chain: Arc Testnet (Chain ID: 5042002)
- USDC: `0x3600000000000000000000000000000000000000` (6 decimals, Arc Testnet)

## Key Files

- `src/App.tsx` — Hash-router, view composition
- `src/components/HomePage.tsx` — Landing page
- `src/components/CreateCircle.tsx` — Circle creation flow (approve + create)
- `src/components/CirclePage.tsx` — Circle detail: members, pot, countdown, contribute/payout/withdraw
- `src/components/MyCircles.tsx` — Lists all circles the connected wallet is a member of
- `src/lib/ajo-contract.ts` — ABI + contract address (VITE_AJO_ADDRESS from .env)
- `src/lib/format.ts` — formatUsdc, shortAddr, formatCountdown, parseUsdcInput
- `src/lib/share.ts` — buildShareLink (Arc Studio iframe-aware share URLs)
- `contracts/AjoCircle.sol` — Factory + circles contract
- `contracts/test/AjoCircle.t.sol` — 38 Foundry unit + fuzz tests
- `contracts/test-helpers/MockERC20.sol` — Standard ERC20 mock
- `contracts/test-helpers/ReentrantMockERC20.sol` — Reentrant ERC20 for reentrancy tests

## Contract Summary

`AjoCircle` is a factory where each circle is stored by a uint256 ID.

Key functions:
- `createCircle(name, contributionAmount, memberCount, roundDuration)` — creator auto-joins + pays collateral
- `join(circleId)` — pay collateral, join pending circle
- `contribute(circleId)` — pay contributionAmount for current round (requires prior USDC approval)
- `payout(circleId)` — callable by anyone; before deadline requires all non-defaulted to have paid; after deadline marks defaulters and slashes their collateral
- `withdraw()` — pull-payment pattern: claim credited USDC (payouts + collateral refunds)
- `cancelCircle(circleId)` — creator can cancel a PENDING circle; refunds all collateral

Security: ReentrancyGuard, SafeERC20, pull-payment for all transfers, no admin, randomness removed (payout = join order only).

## Environment Variables

| Key | Value |
|---|---|
| `VITE_AJO_ADDRESS` | `0xdcef975947fc86f344164dab25af4aaaceb9f0ca` |

## To Run

```bash
bun install
bun run dev
```

## To Test Contracts

```bash
forge test
```
