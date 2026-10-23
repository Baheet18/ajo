import { useState, useEffect } from 'react';
import { useAccount } from 'wagmi';
import { Loader2, Plus, ArrowLeft, Users } from 'lucide-react';
import { motion } from 'framer-motion';
import { AJO_ADDRESS, AJO_ABI } from '@/lib/ajo-contract';
import { formatUsdc } from '@/lib/format';
import { publicClient } from '@/lib/publicClient';

const glass = {
  card: {
    background: 'rgba(255,255,255,0.72)',
    backdropFilter: 'blur(24px) saturate(180%)',
    WebkitBackdropFilter: 'blur(24px) saturate(180%)',
    border: '1px solid rgba(255,255,255,0.68)',
    boxShadow: '0 8px 32px rgba(18,45,69,0.08), inset 0 1px 0 rgba(255,255,255,0.55)',
  } as React.CSSProperties,
  inner: {
    background: 'rgba(255,255,255,0.46)',
    border: '1px solid rgba(255,255,255,0.56)',
  } as React.CSSProperties,
};

const STATUS_LABELS = ['Pending', 'Active', 'Ended'];
const STATUS_COLORS = ['#d97706', '#059669', '#6b7280'];

interface CircleInfo {
  id: bigint;
  name: string;
  contributionAmount: bigint;
  memberCount: number;
  membersLen: number;
  status: number;
  currentRound: number;
  isMember: boolean;
}

interface MyCirclesProps {
  onBack: () => void;
  onCreateCircle: () => void;
  onSelectCircle: (id: bigint) => void;
}

export function MyCircles({ onBack, onCreateCircle, onSelectCircle }: MyCirclesProps) {
  const { address } = useAccount();

  const [circles, setCircles] = useState<CircleInfo[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      setIsLoading(true);
      setError(null);
      try {
        // Read circleCount via publicClient (bypasses wallet RPC)
        const count = await publicClient.readContract({
          address: AJO_ADDRESS,
          abi: AJO_ABI,
          functionName: 'circleCount',
        });

        console.log('[MyCircles] circleCount =', count.toString());

        const total = Number(count);
        const ids: bigint[] = Array.from({ length: total }, (_, i) => BigInt(i + 1));

        // Load all circles in parallel
        const results = await Promise.all(
          ids.map(async (id) => {
            const [rawCircle, isMem] = await Promise.all([
              publicClient.readContract({
                address: AJO_ADDRESS,
                abi: AJO_ABI,
                functionName: 'getCircle',
                args: [id],
              }),
              address
                ? publicClient.readContract({
                    address: AJO_ADDRESS,
                    abi: AJO_ABI,
                    functionName: 'isMember',
                    args: [id, address],
                  })
                : Promise.resolve(false),
            ]);

            const c = rawCircle as {
              name: string;
              contributionAmount: bigint;
              memberCount: bigint | number;
              members: readonly string[];
              status: bigint | number;
              currentRound: bigint | number;
            };

            return {
              id,
              name: c.name,
              contributionAmount: c.contributionAmount,
              memberCount: Number(c.memberCount),
              membersLen: c.members.length,
              status: Number(c.status),
              currentRound: Number(c.currentRound),
              isMember: isMem,
            } satisfies CircleInfo;
          })
        );

        if (!cancelled) {
          // Show newest first; only show circles the user is a member of (or all if no wallet)
          const visible = address ? results.filter((c) => c.isMember) : results;
          setCircles(visible.reverse());
        }
      } catch (e) {
        console.error('[MyCircles] load failed', e);
        if (!cancelled) setError(String(e));
      } finally {
        if (!cancelled) setIsLoading(false);
      }
    }
    void load();
    return () => { cancelled = true; };
  }, [address]);

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <button onClick={onBack} className="flex size-9 items-center justify-center rounded-xl" style={glass.inner}>
          <ArrowLeft className="size-4" style={{ color: 'var(--ink)' }} />
        </button>
        <h2 className="display flex-1 text-xl font-bold" style={{ color: 'var(--ink)', letterSpacing: '-0.02em' }}>
          My circles
        </h2>
        <button
          onClick={onCreateCircle}
          className="flex items-center gap-1.5 rounded-xl px-3 py-2 text-xs font-semibold text-white"
          style={{ background: '#d97706' }}
        >
          <Plus className="size-3.5" />
          New
        </button>
      </div>

      <motion.div
        className="rounded-3xl p-5 space-y-2"
        style={glass.card}
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
      >
        {isLoading ? (
          <div className="flex justify-center py-8">
            <Loader2 className="size-6 animate-spin" style={{ color: '#d97706' }} />
          </div>
        ) : error ? (
          <p className="text-center text-xs py-4 break-all" style={{ color: 'var(--muted)' }}>
            Failed to load: {error}
          </p>
        ) : circles.length === 0 ? (
          <div className="py-8 text-center">
            <Users className="mx-auto mb-3 size-10" style={{ color: 'var(--subtle)' }} />
            <p className="text-sm font-semibold" style={{ color: 'var(--ink)' }}>
              {address ? 'No circles yet' : 'Connect your wallet'}
            </p>
            <p className="mt-1 text-xs" style={{ color: 'var(--muted)' }}>
              {address ? 'Create your first saving group to get started.' : 'Connect to see your circles.'}
            </p>
            {address && (
              <button
                onClick={onCreateCircle}
                className="mt-4 rounded-2xl px-6 py-2.5 text-sm font-semibold text-white"
                style={{ background: 'linear-gradient(135deg, #d97706 0%, #059669 100%)' }}
              >
                Create circle
              </button>
            )}
          </div>
        ) : (
          circles.map((c) => (
            <button
              key={c.id.toString()}
              onClick={() => {
                console.log('[MyCircles] navigating to circle id:', c.id.toString());
                onSelectCircle(c.id);
              }}
              className="w-full rounded-2xl p-4 text-left transition-all hover:scale-[1.01] active:scale-[0.99]"
              style={glass.inner}
            >
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="font-semibold text-sm truncate" style={{ color: 'var(--ink)' }}>
                    {c.name}
                  </p>
                  <p className="text-xs mt-0.5" style={{ color: 'var(--subtle)' }}>
                    #{c.id.toString()} · {formatUsdc(c.contributionAmount)} USDC/round · {c.membersLen}/{c.memberCount} members
                  </p>
                </div>
                <div className="flex flex-col items-end gap-1 shrink-0">
                  <span
                    className="rounded-full px-2 py-0.5 text-xs font-semibold"
                    style={{ background: `${STATUS_COLORS[c.status]}18`, color: STATUS_COLORS[c.status] }}
                  >
                    {STATUS_LABELS[c.status]}
                  </span>
                  {c.status === 1 && (
                    <span className="text-xs" style={{ color: 'var(--muted)' }}>
                      Round {c.currentRound}/{c.memberCount}
                    </span>
                  )}
                </div>
              </div>
            </button>
          ))
        )}
      </motion.div>
    </div>
  );
}
