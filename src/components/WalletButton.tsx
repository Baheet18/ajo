import { useAccount, useConnect, useDisconnect } from 'wagmi';
import { injected } from 'wagmi/connectors';

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

export function WalletButton() {
  const { address, isConnected } = useAccount();
  const { connect, isPending } = useConnect();
  const { disconnect } = useDisconnect();

  if (isConnected && address) {
    return (
      <button
        style={{
          ...btnBase,
          background: 'rgba(255,255,255,0.7)',
          color: '#92400e',
          border: '1px solid rgba(245,158,11,0.3)',
          backdropFilter: 'blur(12px)',
        }}
        onClick={() => disconnect()}
        title="Disconnect wallet"
      >
        <span
          style={{
            width: 8, height: 8, borderRadius: '50%',
            background: '#10b981', flexShrink: 0,
          }}
        />
        {shortAddr(address)}
      </button>
    );
  }

  return (
    <button
      style={{
        ...btnBase,
        background: 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)',
        color: '#fff',
        boxShadow: '0 2px 8px rgba(245,158,11,0.35)',
        opacity: isPending ? 0.7 : 1,
      }}
      disabled={isPending}
      onClick={() => connect({ connector: injected() })}
    >
      {isPending ? 'Connecting…' : 'Connect Wallet'}
    </button>
  );
}
