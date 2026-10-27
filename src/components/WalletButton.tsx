import { useEffect, useState } from 'react';
import { usePrivy, useWallets } from '@privy-io/react-auth';
import { useSetActiveWallet } from '@privy-io/wagmi';
import { useAccount, useBalance } from 'wagmi';
import { formatEther } from 'viem';

/** Truncate 0x… address to 0x1234…abcd */
function shortAddr(addr: string) {
  return addr.slice(0, 6) + '…' + addr.slice(-4);
}

const btnBase: React.CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  gap: '6px',
  padding: '8px 16px',
  borderRadius: '9999px',
  fontWeight: 600,
  fontSize: '14px',
  cursor: 'pointer',
  border: 'none',
  transition: 'opacity 0.15s',
  fontFamily: 'inherit',
};

const ghostBtn: React.CSSProperties = {
  ...btnBase,
  background: 'rgba(255,255,255,0.7)',
  color: '#92400e',
  border: '1px solid rgba(245,158,11,0.3)',
  backdropFilter: 'blur(12px)',
  padding: '6px 12px',
  fontSize: '13px',
};

function useCopy() {
  const [copied, setCopied] = useState(false);
  const copy = (text: string) => {
    void navigator.clipboard?.writeText(text).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    });
  };
  return { copied, copy };
}

/** Keep wagmi's active account in sync with the user's Privy wallet (embedded preferred). */
function useSyncActiveWallet() {
  const { authenticated } = usePrivy();
  const { wallets, ready } = useWallets();
  const { setActiveWallet } = useSetActiveWallet();
  const { address } = useAccount();
  useEffect(() => {
    if (!authenticated || !ready || wallets.length === 0) return;
    const preferred = wallets.find((w) => w.walletClientType === 'privy') ?? wallets[0];
    if (address?.toLowerCase() !== preferred.address.toLowerCase()) {
      void setActiveWallet(preferred);
    }
  }, [authenticated, ready, wallets, address, setActiveWallet]);
}

export function WalletButton() {
  const { ready, authenticated, user, login, logout } = usePrivy();
  const { address } = useAccount();
  const { data: bal } = useBalance({ address, query: { enabled: !!address, refetchInterval: 10_000 } });
  const { copied, copy } = useCopy();
  useSyncActiveWallet();

  if (ready && authenticated) {
    const label = user?.email?.address ?? user?.google?.email ?? (address ? shortAddr(address) : 'Signed in');
    return (
      <div style={{ display: 'inline-flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
        <span style={{ ...ghostBtn, cursor: 'default' }} title={address}>
          <span style={{ width: 8, height: 8, borderRadius: '50%', background: '#10b981', flexShrink: 0 }} />
          {label}
          {bal && <span style={{ opacity: 0.75 }}>· {Number(formatEther(bal.value)).toFixed(2)} USDC</span>}
        </span>
        {address && (
          <button style={ghostBtn} onClick={() => copy(address)} title="Copy address">
            {copied ? 'Copied' : 'Copy address'}
          </button>
        )}
        <button style={ghostBtn} onClick={() => void logout()}>Log out</button>
      </div>
    );
  }

  return (
    <button
      style={{
        ...btnBase,
        background: 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)',
        color: '#fff',
        boxShadow: '0 2px 8px rgba(245,158,11,0.35)',
        opacity: ready ? 1 : 0.7,
      }}
      disabled={!ready}
      onClick={() => login()}
    >
      {ready ? 'Sign in' : 'Loading…'}
    </button>
  );
}

/** Onboarding card shown while the signed-in wallet has 0 native USDC on mainnet. */
export function FundWalletCard() {
  const { authenticated } = usePrivy();
  const { address } = useAccount();
  const { data: bal, isSuccess } = useBalance({ address, query: { enabled: !!address, refetchInterval: 10_000 } });
  const { copied, copy } = useCopy();
  if (!authenticated || !address || !isSuccess || !bal || bal.value > 0n) return null;
  return (
    <div
      style={{
        margin: '12px auto',
        maxWidth: 640,
        padding: '16px 18px',
        borderRadius: 16,
        background: 'rgba(255,251,235,0.9)',
        border: '1px solid rgba(245,158,11,0.35)',
        color: '#78350f',
        fontSize: 14,
      }}
    >
      <div style={{ fontWeight: 700, marginBottom: 6 }}>Get started with USDC on Arc</div>
      <div style={{ marginBottom: 10 }}>
        Send USDC on Arc to this address to get started. This card disappears once USDC arrives.
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
        <code style={{ fontSize: 12, wordBreak: 'break-all', background: 'rgba(255,255,255,0.7)', padding: '4px 8px', borderRadius: 8 }}>{address}</code>
        <button style={ghostBtn} onClick={() => copy(address)}>{copied ? 'Copied!' : 'Copy address'}</button>
      </div>
    </div>
  );
}