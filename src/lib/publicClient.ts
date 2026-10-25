/**
 * A standalone viem public client pinned to Arc Testnet.
 * Used for all READ calls so they work regardless of what chain
 * the user's wallet is currently on (or whether a wallet is connected).
 */
import { createPublicClient, http } from 'viem';
import { arcTestnetChain } from '@/config';

export const publicClient = createPublicClient({
  chain: arcTestnetChain,
  transport: http('https://rpc.testnet.arc.io'),
});
