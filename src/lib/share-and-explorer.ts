export { buildShareLink, getShareBase } from './share';

export function buildTxExplorerUrl(txHash: string): string {
  return `https://explorer.testnet.arc.io/tx/${txHash}`;
}

export function buildAddressExplorerUrl(addr: string): string {
  return `https://explorer.testnet.arc.io/address/${addr}`;
}
