/**
 * A standalone viem public client pinned to Arc Mainnet.
 * Used for all READ calls so they work regardless of what chain
 * the user's wallet is currently on (or whether a wallet is connected).
 */
import { createPublicClient, http } from 'viem';
import { arcChain } from '@/config';

export const publicClient = createPublicClient({
  chain: arcChain,
  transport: http('https://rpc.mainnet.arc.io'),
});
