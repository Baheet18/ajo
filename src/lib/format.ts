/** Format a bigint USDC amount (6 decimals) into a human string like "25.00" */
export function formatUsdc(raw: bigint): string {
  const abs = raw < 0n ? -raw : raw;
  const whole = abs / 1_000_000n;
  const frac = abs % 1_000_000n;
  const fracStr = frac.toString().padStart(6, '0').slice(0, 2);
  const neg = raw < 0n ? '-' : '';
  return `${neg}${whole.toLocaleString()}.${fracStr}`;
}

/** Format a wallet address as 0x1234...5678 */
export function shortAddr(addr: string): string {
  if (!addr || addr.length < 10) return addr;
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

/** Format seconds remaining into "Xh Ym Zs" */
export function formatCountdown(seconds: number): string {
  if (seconds <= 0) return 'Deadline passed';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}h ${m}m ${s}s`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

/** Parse a USDC decimal string into bigint (6 decimals). Returns null on invalid input. */
export function parseUsdcInput(value: string): bigint | null {
  const trimmed = value.trim();
  if (!/^\d+(\.\d{0,6})?$/.test(trimmed)) return null;
  const [whole, frac = ''] = trimmed.split('.');
  const fracPadded = frac.padEnd(6, '0').slice(0, 6);
  return BigInt(whole) * 1_000_000n + BigInt(fracPadded);
}

export const ZERO_ADDR = '0x0000000000000000000000000000000000000000';
