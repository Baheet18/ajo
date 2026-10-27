/**
 * wagmi configuration — Arc Studio
 *
 * Arc Mainnet — USDC is the native gas token (18 decimals).
 * Chain ID 5042, RPC https://rpc.mainnet.arc.io
 */

import { http } from 'wagmi'
import { createConfig } from '@privy-io/wagmi'
import { defineChain } from 'viem'
import { registerChain } from './tracing'

const ARC_RPC = 'https://rpc.mainnet.arc.io'

export const arcChain = defineChain({
  id: 5042,
  name: 'Arc',
  nativeCurrency: { name: 'USDC', symbol: 'USDC', decimals: 18 },
  rpcUrls: {
    default: { http: [ARC_RPC] },
  },
  blockExplorers: {
    default: {
      name: 'Arc Explorer',
      url: 'https://explorer.arc.io',
    },
  },
  testnet: false,
})

registerChain(arcChain.id, ARC_RPC)

export const config = createConfig({
  chains: [arcChain],
  transports: {
    [arcChain.id]: http(ARC_RPC),
  },
})

// Keep backward-compat alias used in some components
export const arcTestnetChain = arcChain
