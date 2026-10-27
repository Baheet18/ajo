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
| AjoCircle v4b (deprecated) | Arc Testnet | `0x6c98eb49ada2ea1b6cd408d825cb1933f2d0ff40` | [View](https://explorer.testnet.arc.io/address/0x6c98eb49ada2ea1b6cd408d825cb1933f2d0ff40) |
| AjoCircle v5 (Arc Testnet — superseded) | Arc Testnet | `0x64822c48a4de920e74d16df88cb3b0b6924819d6` | [View](https://explorer.testnet.arc.io/address/0x64822c48a4de920e74d16df88cb3b0b6924819d6) |
| **AjoCircle v6 (mainnet — not yet deployed)** | Arc Mainnet | _deploy and set `VITE_AJO_ADDRESS`_ | — |

Full deployment history (with tx hashes) is in `contracts/contract-metadata/AjoCircle.json`.

## Flattened Source for Verification

`docs/AjoCircle_flat.sol` — flattened AjoCircle for manual deployment or block explorer verification.

**Compiler settings (exact, required for verification):**
- Compiler: `solc 0.8.28`
- Optimizer: enabled, 200 runs
- EVM version: `paris`
- Via IR: `true`

## Tech Stack

- Frontend: React 18, Vite, TypeScript, Tailwind CSS, Bun
- Web3: wagmi v2, viem v2
- Sign-in: Privy (`@privy-io/react-auth` + `@privy-io/wagmi`) — email, Google, or an external wallet. Users without a wallet get a Privy embedded wallet.
- Contracts: Solidity ^0.8.20 + Foundry. Sources in `contracts/`, unit + fuzz tests in `contracts/test/` (82 tests).
- Chain: Arc Mainnet (Chain ID: 5042), single RPC `https://rpc.mainnet.arc.io`
- USDC: native gas token on Arc (18 decimals on-chain). The contract stores all amounts in 6-decimal USDC units and scales by `1e12` for `msg.value` and payouts.

## Key Files

- `src/main.tsx` — Privy + wagmi + react-query providers
- `src/config.ts` — Arc Mainnet chain definition and wagmi config (via `@privy-io/wagmi`)
- `src/App.tsx` — Hash-router, view composition, Mainnet badge
- `src/components/HomePage.tsx` — Landing page, join-by-ID
- `src/components/CreateCircle.tsx` — Circle creation: contribution (default 1 USDC), size, round length, trust level (holdback), optional deposit. One signature.
- `src/components/CirclePage.tsx` — Circle detail: members, pot, countdown, holdbacks, reputation, contribute/payout/withdraw, invite link, leave button (non-creator PENDING), payout order (creator can reorder while PENDING)
- `src/components/MyCircles.tsx` — Circles the connected wallet is a member of
- `src/components/WalletButton.tsx` — Privy login/logout, address + balance, keeps wagmi active wallet in sync; zero-balance card shows address to fund
- `src/lib/ajo-contract.ts` — ABI + contract address (`VITE_AJO_ADDRESS`), chain ID 5042
- `src/lib/format.ts` — formatUsdc, shortAddr, formatCountdown, parseUsdcInput
- `contracts/AjoCircle.sol` — Factory + circles contract (v6: leave, setPayoutOrder, expiry)
- `contracts/test/AjoCircle.Base.t.sol` — Shared test base
- `contracts/test/AjoCircle.Core.t.sol` — Core tests (35)
- `contracts/test/AjoCircle.Holdback.t.sol` — Holdback / default tests (23)
- `contracts/test/AjoCircle.Leave.t.sol` — Leave / setPayoutOrder / expiry tests (24)
- `docs/AjoCircle_flat.sol` — Flattened source for deployment/verification

## Contract Summary (v6)

`AjoCircle` is a factory where each circle is stored by a `uint256` ID. No owner, no admin, not upgradeable.

Key functions (all payments are native USDC via `msg.value`; no approvals):
- `createCircle(name, contributionAmount, memberCount, roundDuration, collateralAmount, holdbackBps)` — creator auto-joins and pays the deposit (if any).
- `join(circleId)` — join a PENDING circle, paying `collateralAmount` (or 0). Reverts if the pending circle has expired (7 days).
- `leave(circleId)` — non-creator members may leave a PENDING circle; collateral is refunded to `pendingWithdrawals`.
- `setPayoutOrder(circleId, address[] order)` — creator-only, PENDING-only. Sets the payout sequence. Late joiners are appended. Order locks when the circle becomes ACTIVE.
- `cancelCircle(circleId)` — creator cancels any time while PENDING, OR any member may cancel after 7 days (pending expiry).
- `contribute(circleId)` — pay `contributionAmount` for the current round before the deadline. Releases one round's holdback share.
- `payout(circleId)` — trigger round payout. Early (all paid) or after deadline (defaulters slashed).
- `withdraw()` — pull payment: claim everything credited.
- `getMemberReputation(member)` — global rounds paid / missed / circles completed.

## Environment Variables

| Key | Default | Notes |
|---|---|---|
| `VITE_AJO_ADDRESS` | `0x000...000` | Set to deployed mainnet address before building |
| `VITE_PRIVY_APP_ID` | `cmvnjxpu101zd0gjpmi5ruvlj` | Fallback in `src/main.tsx`; deployed domain must be allowed in Privy dashboard |
| `VITE_PUBLIC_URL` | empty | Optional override for invite links; when empty they use the current site's origin |

## To Run

```bash
bun install
bun run dev
```

## To Check

```bash
bun run check
```

## To Test Contracts

```bash
forge test
```

## Mainnet Deployment Steps

1. Set `VITE_AJO_ADDRESS` in `.env` to the deployed contract address.
2. Allow `ajo-usdc.vercel.app` (or your domain) in the Privy dashboard under "Allowed origins".
3. Build: `bun run build`
4. Verify the contract on Arc Explorer using the flattened source in `docs/AjoCircle_flat.sol` with the exact compiler settings above.
