# Ajo — Rotating Savings Group on Arc

> Built with Arc Studio — money-powered apps in minutes

A rotating savings group (ajo/esusu) dapp where groups of 2–10 members save together in USDC. Everyone contributes each round; the pot goes to the next person in the payout order (join order).

Live: https://ajo-two-psi.vercel.app

---

## Deployed Contracts

| Contract | Chain | Address | Explorer |
|---|---|---|---|
| AjoCircle v1 (deprecated) | Arc Testnet | `0xdcef975947fc86f344164dab25af4aaaceb9f0ca` | [View](https://explorer.testnet.arc.io/address/0xdcef975947fc86f344164dab25af4aaaceb9f0ca) |
| AjoCircle v2 (deprecated) | Arc Testnet | `0xd78cd3378823ed3963a95ea4f9d88352001b8b62` | [View](https://explorer.testnet.arc.io/address/0xd78cd3378823ed3963a95ea4f9d88352001b8b62) |
| AjoCircle v3 (deprecated) | Arc Testnet | `0xf4a21b74f442f9672a1787fed6ebfcdfb73cd8a2` | [View](https://explorer.testnet.arc.io/address/0xf4a21b74f442f9672a1787fed6ebfcdfb73cd8a2) |
| AjoCircle v4 (deprecated) | Arc Testnet | `0x1db5c7c8f2ab1bb84674024e952a151240e136ab` | [View](https://explorer.testnet.arc.io/address/0x1db5c7c8f2ab1bb84674024e952a151240e136ab) |
| AjoCircle (deprecated, superseded same day by v5) | Arc Testnet | `0x6c98eb49ada2ea1b6cd408d825cb1933f2d0ff40` | [View](https://explorer.testnet.arc.io/address/0x6c98eb49ada2ea1b6cd408d825cb1933f2d0ff40) |
| **AjoCircle v5 (current)** — holdback, reputation, early payout, native USDC | Arc Testnet | `0x64822c48a4de920e74d16df88cb3b0b6924819d6` | [View](https://explorer.testnet.arc.io/address/0x64822c48a4de920e74d16df88cb3b0b6924819d6) |

Full deployment history (with tx hashes) is in `contracts/contract-metadata/AjoCircle.json`.

## Tech Stack

- Frontend: React 18, Vite, TypeScript, Tailwind CSS, Bun
- Web3: wagmi v2, viem v2
- Sign-in: Privy (`@privy-io/react-auth` + `@privy-io/wagmi`) — email, Google, or an external wallet. Users without a wallet get a Privy embedded wallet, which is preferred as the active wagmi account.
- Contracts: Solidity ^0.8.20 + Foundry. Sources in `contracts/`, unit + fuzz tests in `contracts/test/` (58 tests).
- Chain: Arc Testnet (Chain ID: 5042002), single RPC `https://rpc.testnet.arc.io`
- USDC: native gas token on Arc (18 decimals on-chain). The contract stores all amounts in 6-decimal USDC units and scales by `1e12` for `msg.value` and payouts.

## Key Files

- `src/main.tsx` — Privy + wagmi + react-query providers
- `src/config.ts` — Arc Testnet chain definition and wagmi config (via `@privy-io/wagmi`)
- `src/App.tsx` — Hash-router, view composition
- `src/components/HomePage.tsx` — Landing page, join-by-ID
- `src/components/CreateCircle.tsx` — Circle creation: contribution, size, round length, trust level (holdback), optional deposit. One signature (native USDC sent as `value`).
- `src/components/CirclePage.tsx` — Circle detail: members, pot, countdown, holdbacks, reputation, contribute/payout/withdraw, invite link
- `src/components/MyCircles.tsx` — Circles the connected wallet is a member of
- `src/components/WalletButton.tsx` — Privy login/logout, address + balance, keeps wagmi's active wallet in sync
- `src/lib/ajo-contract.ts` — ABI + contract address (`VITE_AJO_ADDRESS`)
- `src/lib/format.ts` — formatUsdc, shortAddr, formatCountdown, parseUsdcInput
- `src/lib/share.ts` — Arc Studio scaffold helper (buildShareLink); currently unused. Invite links are built in `CreateCircle.tsx` / `CirclePage.tsx` from `VITE_PUBLIC_URL` or the current site's origin.
- `contracts/AjoCircle.sol` — Factory + circles contract
- `contracts/AjoCircle-design.md` — Contract design: money flows, holdback, defaults, security
- `contracts/test/AjoCircle.Base.t.sol` — Shared test base (setUp, actors, helpers)
- `contracts/test/AjoCircle.Core.t.sol` — create / join / contribute / payout / cancel / views / fuzz (35 tests)
- `contracts/test/AjoCircle.Holdback.t.sol` — holdback, friends mode, defaults, early payout, reputation, reentrancy, invariants (23 tests)
- `contracts/test-helpers/ReentrantWithdraw.sol` — Reentrancy attacker for `withdraw()`
- `contracts/test/AjoCircle.t.sol`, `AjoCircle.Bond.t.sol`, `test-helpers/MockERC20.sol`, `ReentrantMockERC20.sol` — leftovers from the ERC-20 era; contain no tests / are unused

## Contract Summary

`AjoCircle` is a factory where each circle is stored by a `uint256` ID. No owner, no admin, not upgradeable.

Key functions (all payments are native USDC via `msg.value`; no approvals):
- `createCircle(name, contributionAmount, memberCount, roundDuration, collateralAmount, holdbackBps)` — creator auto-joins and pays the deposit (if any). `memberCount` 2–10, `roundDuration` ≥ 300s, `holdbackBps` ≤ 3000 (30%).
- `join(circleId)` — join a PENDING circle, paying `collateralAmount` (or 0). Circle starts when full.
- `contribute(circleId)` — pay `contributionAmount` for the current round before the deadline. If the member has holdback locked, one round's share is released to them.
- `payout(circleId)` — anyone may call. Before the deadline it requires every non-defaulted member except the recipient to have paid (early payout). After the deadline it slashes non-payers (holdback first, then deposit) into the pot. The recipient receives the pot minus holdback.
- `withdraw()` — pull payment: claim everything credited (payouts, released holdback, refunds).
- `cancelCircle(circleId)` — creator cancels a PENDING circle; deposits refunded.
- `getMemberReputation(member)` — global rounds paid / missed / circles completed.

Trust level presets in the UI map to `holdbackBps`: Friends = 0%, Mixed = 10%, Strangers = 25%, or custom up to 30%.

Security: ReentrancyGuard on all state-changing entry points, checks-effects-interactions, pull payments only, loops bounded by `memberCount ≤ 10`, payout order = join order (no randomness).

## Environment Variables

| Key | Default | Notes |
|---|---|---|
| `VITE_AJO_ADDRESS` | `0x64822c48a4de920e74d16df88cb3b0b6924819d6` | Baked in by `vite.config.ts` if unset |
| `VITE_PRIVY_APP_ID` | `cmvnjxpu101zd0gjpmi5ruvlj` | Fallback in `src/main.tsx`; the deployed domain must be allowed in the Privy dashboard |
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
