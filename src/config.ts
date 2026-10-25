/**
 * wagmi configuration — Arc Studio
 *
 * We define a custom arcTestnet chain that contains ONLY the canonical
 * https://rpc.testnet.arc.io endpoint. This is critical: viem/chains'
 * arcTestnet lists several RPC URLs; MetaMask picks whichever it likes
 * when wallet_addEthereumChain is called, and some of those alternates
 * return 404. Locking it to one URL prevents that.
 */

import { http } from 'wagmi'
import { createConfig } from '@privy-io/wagmi'
import { defineChain } from 'viem'
import { registerChain } from './tracing'

const ARC_TESTNET_RPC = 'https://rpc.testnet.arc.io'

export const arcTestnetChain = defineChain({
  id: 5042002,
  name: 'Arc Testnet',
  nativeCurrency: { name: 'USDC', symbol: 'USDC', decimals: 18 },
  rpcUrls: {
    default: { http: [ARC_TESTNET_RPC] },
  },
  blockExplorers: {
    default: {
      name: 'Arc Explorer',
      url: 'https://explorer.testnet.arc.io',
    },
  },
  testnet: true,
})

registerChain(arcTestnetChain.id, ARC_TESTNET_RPC)

export const config = createConfig({
  chains: [arcTestnetChain],
  transports: {
    [arcTestnetChain.id]: http(ARC_TESTNET_RPC),
  },
})
