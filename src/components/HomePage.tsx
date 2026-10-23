import { useState } from 'react';
import { WalletButton } from '@/components/WalletButton';
import { useAccount } from 'wagmi';
import { Users, Plus, ArrowRight } from 'lucide-react';
import { motion } from 'framer-motion';

const glass = {
  card: {
    background: 'rgba(255,255,255,0.72)',
    backdropFilter: 'blur(24px) saturate(180%)',
    WebkitBackdropFilter: 'blur(24px) saturate(180%)',
    border: '1px solid rgba(255,255,255,0.68)',
    boxShadow: '0 8px 32px rgba(18,45,69,0.08), inset 0 1px 0 rgba(255,255,255,0.55)',
  } as React.CSSProperties,
};

interface HomePageProps {
  onCreateCircle: () => void;
  onMyCircles: () => void;
}

export function HomePage({ onCreateCircle, onMyCircles }: HomePageProps) {
  const { isConnected } = useAccount();
  const [joinId, setJoinId] = useState('');

  return (
    <div className="space-y-5">
      {/* Hero card */}
      <motion.section
        className="rounded-3xl p-6 text-center"
        style={glass.card}
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4 }}
      >
        {/* Adire-inspired geometric accent */}
        <div
          className="mx-auto mb-4 flex size-16 items-center justify-center rounded-2xl"
          style={{
            background: 'linear-gradient(135deg, #f59e0b 0%, #10b981 100%)',
            boxShadow: '0 4px 16px rgba(245,158,11,0.3)',
          }}
        >
          <Users className="size-8 text-white" />
        </div>

        <h1
          className="display mb-2 text-3xl font-bold"
          style={{ color: 'var(--ink)', letterSpacing: '-0.03em' }}
        >
          Save together
          <br />
          <span style={{ color: '#d97706' }}>in dollars.</span>
        </h1>

        <p className="mx-auto mb-5 max-w-xs text-sm" style={{ color: 'var(--muted)' }}>
          Ajo is a rotating savings group. Everyone contributes each round — one person receives the
          full pot. Built on Arc with USDC.
        </p>

        <div className="flex flex-col gap-3">
          {isConnected ? (
            <>
              <motion.button
                onClick={onCreateCircle}
                className="flex w-full items-center justify-center gap-2 rounded-2xl py-3.5 text-sm font-semibold text-white transition-all hover:scale-[1.01] active:scale-[0.99]"
                style={{ background: 'linear-gradient(135deg, #d97706 0%, #059669 100%)' }}
                whileHover={{ scale: 1.01 }}
                whileTap={{ scale: 0.99 }}
              >
                <Plus className="size-4" />
                Create a circle
              </motion.button>
              <button
                onClick={onMyCircles}
                className="flex w-full items-center justify-center gap-2 rounded-2xl py-3 text-sm font-semibold transition-all hover:scale-[1.01] active:scale-[0.99]"
                style={{
                  background: 'rgba(255,255,255,0.6)',
                  border: '1px solid rgba(217,119,6,0.25)',
                  color: 'var(--ink)',
                }}
              >
                <Users className="size-4" />
                My circles
                <ArrowRight className="size-3.5" />
              </button>
            </>
          ) : (
            <div className="flex flex-col items-center gap-3">
              <p className="text-xs" style={{ color: 'var(--subtle)' }}>
                Connect your wallet to get started
              </p>
              <WalletButton />
            </div>
          )}
        </div>
      </motion.section>

      {/* Join by ID */}
      {isConnected && (
        <motion.section
          className="rounded-2xl p-4"
          style={glass.card}
          initial={{ opacity: 0, y: 10 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.4, delay: 0.1 }}
        >
          <p className="mb-2 text-xs font-semibold" style={{ color: 'var(--muted)' }}>
            HAVE AN INVITE?
          </p>
          <div className="flex gap-2">
            <input
              type="text"
              placeholder="Circle ID or link"
              value={joinId}
              onChange={(e) => {
                // extract numeric ID from a URL if pasted
                const val = e.target.value;
                const match = val.match(/[?&]circle=(\d+)/) || val.match(/\/circle\/(\d+)/);
                setJoinId(match ? match[1] : val);
              }}
              className="flex-1 rounded-xl border px-3 py-2 text-sm outline-none focus:ring-2"
              style={{
                borderColor: 'rgba(18,45,69,0.15)',
                background: 'rgba(255,255,255,0.5)',
                color: 'var(--ink)',
              }}
            />
            <button
              disabled={!joinId.trim()}
              onClick={() => {
                const id = joinId.trim().replace(/\D/g, '');
                if (id) window.location.hash = `#circle/${id}`;
              }}
              className="rounded-xl px-4 py-2 text-sm font-semibold text-white disabled:opacity-40"
              style={{ background: '#d97706' }}
            >
              Go
            </button>
          </div>
        </motion.section>
      )}

      {/* How it works */}
      <motion.section
        className="rounded-2xl p-4"
        style={glass.card}
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, delay: 0.15 }}
      >
        <p className="mb-3 text-xs font-semibold" style={{ color: 'var(--muted)' }}>
          HOW IT WORKS
        </p>
        <div className="space-y-2.5">
          {[
            ['1', 'Create a circle with your group — set the amount, size, and cadence.'],
            ['2', 'Everyone joins and locks a security deposit.'],
            ['3', 'Each round, everyone contributes. The pot goes to the next person in line.'],
            ['4', 'After all rounds complete, deposits are refunded. No one left behind.'],
          ].map(([num, text]) => (
            <div key={num} className="flex gap-3">
              <span
                className="display flex size-5 shrink-0 items-center justify-center rounded-full text-xs font-bold text-white"
                style={{ background: '#d97706', marginTop: 1 }}
              >
                {num}
              </span>
              <p className="text-xs leading-relaxed" style={{ color: 'var(--ink-2)' }}>
                {text}
              </p>
            </div>
          ))}
        </div>
      </motion.section>
    </div>
  );
}
