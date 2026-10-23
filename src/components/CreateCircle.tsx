import { useState, useEffect } from 'react';
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useReadContract, useSwitchChain } from 'wagmi';
import { erc20Abi } from 'viem';
import { publicClient } from '@/lib/publicClient';
import { toast } from 'sonner';
import { ArrowLeft, Copy, Check, Shield } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { AJO_ADDRESS, AJO_ABI, AJO_CHAIN_ID, USDC_ADDRESS } from '@/lib/ajo-contract';
import { parseUsdcInput, formatUsdc } from '@/lib/format';

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

const DURATION_OPTIONS = [
  { label: '5 min (demo)', value: 300 },
  { label: '1 day', value: 86400 },
  { label: '1 week', value: 604800 },
  { label: '2 weeks', value: 1209600 },
  { label: '1 month', value: 2592000 },
];

interface CreateCircleProps {
  onBack: () => void;
  onCreated: (circleId: bigint) => void;
}

// keccak256('CircleCreated(uint256,address,string,uint256,uint8,uint256)')
const CIRCLE_CREATED_TOPIC =
  '0xd333ebc5974fb8cf4bad87d6065783f241c24993e24e84935acee3fb4849c31e' as const;

export function CreateCircle({ onBack, onCreated }: CreateCircleProps) {
  const { address, chainId } = useAccount();
  const { switchChain } = useSwitchChain();
  const wrongChain = chainId !== AJO_CHAIN_ID;

  const [name, setName] = useState('');
  const [contributionStr, setContributionStr] = useState('');
  const [memberCount, setMemberCount] = useState(3);
  const [roundDuration, setRoundDuration] = useState(604800);
  const [customDuration, setCustomDuration] = useState('');
  // Collateral toggle — default OFF. When OFF, collateral = contribution amount (contract default).
  // When ON, user sets a custom collateral amount (separate field).
  const [collateralOn, setCollateralOn] = useState(false);
  const [collateralStr, setCollateralStr] = useState('');
  const [createdId, setCreatedId] = useState<bigint | null>(null);
  const [shareLink, setShareLink] = useState('');
  const [copied, setCopied] = useState(false);
  const [approvalDone, setApprovalDone] = useState(false);
  const [toastShown, setToastShown] = useState(false);

  const contributionAmount = parseUsdcInput(contributionStr);
  // Collateral: when toggle OFF → 0 (no collateral). When ON → use custom field or fallback to contribution.
  const collateralAmount = collateralOn
    ? (parseUsdcInput(collateralStr) ?? contributionAmount ?? 0n)
    : 0n;

  const effectiveDuration = customDuration.trim()
    ? parseInt(customDuration) || roundDuration
    : roundDuration;

  const isFormValid =
    name.trim().length > 0 &&
    contributionAmount !== null &&
    contributionAmount > 0n &&
    memberCount >= 2 &&
    memberCount <= 10 &&
    effectiveDuration >= 300 &&
    (!collateralOn || (parseUsdcInput(collateralStr) !== null && (parseUsdcInput(collateralStr) ?? 0n) > 0n));

  // Total USDC needed at join: contribution (collateral deposit) + first round contribution.
  // Contract charges contributionAmount at join as deposit, then contributionAmount per round.
  // We need approval for: collateral (if any) + at least one round contribution.
  const approvalNeeded = collateralAmount + (contributionAmount ?? 0n) * BigInt(memberCount + 5);

  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: USDC_ADDRESS,
    abi: erc20Abi,
    functionName: 'allowance',
    args: address ? [address, AJO_ADDRESS] : undefined,
    chainId: AJO_CHAIN_ID,
    query: { enabled: !!address },
  });

  const needsApproval = approvalNeeded > 0n && (allowance == null || allowance < approvalNeeded);

  const { writeContract: writeApprove, data: approveTxHash, isPending: isApprovePending, reset: resetApprove } = useWriteContract();
  const { isLoading: isApproveConfirming, isSuccess: isApproveSuccess } = useWaitForTransactionReceipt({ hash: approveTxHash });
  const { writeContract: writeCreate, data: createTxHash, isPending: isCreatePending, reset: resetCreate } = useWriteContract();
  const { isLoading: isCreateConfirming, isSuccess: isCreateSuccess } = useWaitForTransactionReceipt({ hash: createTxHash });

  useEffect(() => {
    if (isApproveSuccess && !approvalDone) {
      setApprovalDone(true);
      void refetchAllowance();
      if (!toastShown) { toast.success('Approval confirmed'); setToastShown(true); }
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isApproveSuccess]);

  useEffect(() => {
    if (!isCreateSuccess || !createTxHash || createdId !== null) return;
    void (async () => {
      try {
        const receipt = await publicClient.getTransactionReceipt({ hash: createTxHash });
        const log = receipt.logs.find(
          l => l.address.toLowerCase() === AJO_ADDRESS.toLowerCase() &&
               l.topics[0] === CIRCLE_CREATED_TOPIC
        );
        if (!log?.topics[1]) { console.error('[CreateCircle] CircleCreated log not found'); return; }
        const id = Number(BigInt(log.topics[1]));
        if (id <= 0 || id > 1_000_000) { console.error('[CreateCircle] id out of range:', id); return; }
        setCreatedId(BigInt(id));
        const base = (import.meta.env.VITE_PUBLIC_URL as string) || location.origin;
        setShareLink(`${base}#circle/${id}`);
      } catch (e) { console.error('[CreateCircle] receipt error', e); }
    })();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isCreateSuccess, createTxHash]);

  function handleApprove() {
    if (wrongChain) { switchChain({ chainId: AJO_CHAIN_ID }); return; }
    writeApprove({ address: USDC_ADDRESS, abi: erc20Abi, functionName: 'approve', args: [AJO_ADDRESS, approvalNeeded], chainId: AJO_CHAIN_ID });
  }

  function handleCreate() {
    if (!isFormValid || !contributionAmount) return;
    if (wrongChain) { switchChain({ chainId: AJO_CHAIN_ID }); return; }
    writeCreate({
      address: AJO_ADDRESS, abi: AJO_ABI, functionName: 'createCircle',
      args: [name.trim(), contributionAmount, memberCount, BigInt(effectiveDuration)],
      chainId: AJO_CHAIN_ID,
    });
  }

  function handleCopy() {
    void navigator.clipboard.writeText(shareLink).then(() => { setCopied(true); setTimeout(() => setCopied(false), 2000); });
  }

  function handleReset() { resetApprove(); resetCreate(); setApprovalDone(false); setToastShown(false); }

  const isBusy = isApprovePending || isApproveConfirming || isCreatePending || isCreateConfirming;
  const isDone = isCreateSuccess && createdId !== null;
  const isApproving = isApprovePending || isApproveConfirming;
  const isCreating = isCreatePending || isCreateConfirming;
  const showCreateBtn = approvalDone || !needsApproval;

  if (isDone && createdId !== null) {
    return (
      <motion.div className="space-y-4" initial={{ opacity: 0, scale: 0.97 }} animate={{ opacity: 1, scale: 1 }}>
        <div className="rounded-3xl p-6 text-center" style={glass.card}>
          <div className="mx-auto mb-3 flex size-14 items-center justify-center rounded-2xl" style={{ background: 'linear-gradient(135deg, #d97706 0%, #059669 100%)' }}>
            <Check className="size-7 text-white" />
          </div>
          <h2 className="display mb-1 text-2xl font-bold" style={{ color: 'var(--ink)', letterSpacing: '-0.02em' }}>Circle created!</h2>
          <p className="mb-4 text-sm" style={{ color: 'var(--muted)' }}>Circle #{createdId.toString()} · Share the link to invite members</p>
          <div className="mb-4 flex items-center gap-2 rounded-2xl p-3" style={glass.inner}>
            <span className="flex-1 truncate text-xs font-mono" style={{ color: 'var(--ink-2)' }}>{shareLink || 'Loading link...'}</span>
            <button onClick={handleCopy} className="flex shrink-0 items-center gap-1 rounded-lg px-3 py-1.5 text-xs font-semibold" style={{ background: '#d97706', color: 'white' }}>
              {copied ? <Check className="size-3" /> : <Copy className="size-3" />}
              {copied ? 'Copied' : 'Copy'}
            </button>
          </div>
          <button onClick={() => onCreated(createdId)} className="w-full rounded-2xl py-3.5 text-sm font-semibold text-white" style={{ background: 'linear-gradient(135deg, #d97706 0%, #059669 100%)' }}>
            View circle
          </button>
        </div>
      </motion.div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <button onClick={onBack} className="flex size-9 items-center justify-center rounded-xl" style={glass.inner}>
          <ArrowLeft className="size-4" style={{ color: 'var(--ink)' }} />
        </button>
        <h2 className="display text-xl font-bold" style={{ color: 'var(--ink)', letterSpacing: '-0.02em' }}>New circle</h2>
      </div>

      <motion.div className="rounded-3xl p-5 space-y-4" style={glass.card} initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }}>

        {/* Name */}
        <div>
          <label className="mb-1.5 block text-xs font-semibold" style={{ color: 'var(--muted)' }}>CIRCLE NAME</label>
          <input
            value={name} onChange={(e) => setName(e.target.value)}
            placeholder="Family savings, Work crew..."
            className="w-full rounded-xl border px-3 py-2.5 text-sm outline-none focus:ring-2"
            style={{ borderColor: 'rgba(18,45,69,0.15)', background: 'rgba(255,255,255,0.5)', color: 'var(--ink)' }}
          />
        </div>

        {/* Contribution */}
        <div>
          <label className="mb-1.5 block text-xs font-semibold" style={{ color: 'var(--muted)' }}>CONTRIBUTION PER ROUND (USDC)</label>
          <div className="relative">
            <input
              inputMode="decimal" value={contributionStr}
              onChange={(e) => { const v = e.target.value.replace(/[^0-9.]/g, ''); if (v === '' || /^\d*\.?\d{0,6}$/.test(v)) setContributionStr(v); }}
              placeholder="0.00"
              className="w-full rounded-xl border py-2.5 pl-3 pr-16 text-sm outline-none focus:ring-2"
              style={{ borderColor: 'rgba(18,45,69,0.15)', background: 'rgba(255,255,255,0.5)', color: 'var(--ink)' }}
            />
            <span className="absolute right-3 top-1/2 -translate-y-1/2 text-xs font-semibold" style={{ color: 'var(--subtle)' }}>USDC</span>
          </div>
        </div>

        {/* Member count */}
        <div>
          <label className="mb-1.5 block text-xs font-semibold" style={{ color: 'var(--muted)' }}>MEMBERS (2–10)</label>
          <div className="flex gap-2">
            {[2, 3, 4, 5, 6, 8, 10].map((n) => (
              <button key={n} onClick={() => setMemberCount(n)} className="flex-1 rounded-xl py-2 text-sm font-semibold transition-all"
                style={{ background: memberCount === n ? '#d97706' : 'rgba(255,255,255,0.5)', color: memberCount === n ? 'white' : 'var(--ink)', border: '1px solid', borderColor: memberCount === n ? '#d97706' : 'rgba(18,45,69,0.1)' }}>
                {n}
              </button>
            ))}
          </div>
        </div>

        {/* Round duration */}
        <div>
          <label className="mb-1.5 block text-xs font-semibold" style={{ color: 'var(--muted)' }}>ROUND DURATION</label>
          <div className="grid grid-cols-2 gap-2">
            {DURATION_OPTIONS.map(({ label, value }) => (
              <button key={value} onClick={() => { setRoundDuration(value); setCustomDuration(''); }} className="rounded-xl py-2 text-xs font-semibold transition-all"
                style={{ background: roundDuration === value && !customDuration ? '#d97706' : 'rgba(255,255,255,0.5)', color: roundDuration === value && !customDuration ? 'white' : 'var(--ink)', border: '1px solid', borderColor: roundDuration === value && !customDuration ? '#d97706' : 'rgba(18,45,69,0.1)' }}>
                {label}
              </button>
            ))}
            <input type="number" min={300} value={customDuration} onChange={(e) => setCustomDuration(e.target.value)} placeholder="Custom (sec)"
              className="col-span-1 rounded-xl border px-2 py-2 text-xs outline-none"
              style={{ borderColor: 'rgba(18,45,69,0.15)', background: 'rgba(255,255,255,0.5)', color: 'var(--ink)' }} />
          </div>
        </div>

        {/* Collateral toggle */}
        <div className="rounded-2xl p-4 space-y-3" style={glass.inner}>
          <div className="flex items-center justify-between gap-3">
            <div className="flex items-center gap-2">
              <Shield className="size-4 shrink-0" style={{ color: collateralOn ? '#d97706' : 'var(--subtle)' }} />
              <div>
                <p className="text-xs font-semibold" style={{ color: 'var(--ink)' }}>Security deposit</p>
                <p className="text-xs" style={{ color: 'var(--subtle)' }}>Held at join, refunded at cycle end</p>
              </div>
            </div>
            {/* Toggle switch */}
            <button
              role="switch"
              aria-checked={collateralOn}
              onClick={() => setCollateralOn(!collateralOn)}
              className="relative h-6 w-11 shrink-0 rounded-full transition-colors duration-200"
              style={{ background: collateralOn ? '#d97706' : 'rgba(18,45,69,0.15)' }}
            >
              <span
                className="absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-transform duration-200"
                style={{ transform: collateralOn ? 'translateX(20px)' : 'translateX(2px)' }}
              />
            </button>
          </div>

          <AnimatePresence>
            {collateralOn && (
              <motion.div initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} exit={{ opacity: 0, height: 0 }} className="overflow-hidden">
                <div className="pt-1 space-y-2">
                  <div className="relative">
                    <input
                      inputMode="decimal" value={collateralStr}
                      onChange={(e) => { const v = e.target.value.replace(/[^0-9.]/g, ''); if (v === '' || /^\d*\.?\d{0,6}$/.test(v)) setCollateralStr(v); }}
                      placeholder="0.00"
                      className="w-full rounded-xl border py-2.5 pl-3 pr-16 text-sm outline-none focus:ring-2"
                      style={{ borderColor: 'rgba(18,45,69,0.15)', background: 'rgba(255,255,255,0.5)', color: 'var(--ink)' }}
                    />
                    <span className="absolute right-3 top-1/2 -translate-y-1/2 text-xs font-semibold" style={{ color: 'var(--subtle)' }}>USDC</span>
                  </div>
                  <p className="text-xs leading-relaxed" style={{ color: 'var(--muted)' }}>
                    Each member locks this deposit when joining. It covers missed payments and is refunded when the cycle ends.
                  </p>
                </div>
              </motion.div>
            )}
            {!collateralOn && (
              <motion.p initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="text-xs" style={{ color: 'var(--subtle)' }}>
                No deposit required. Members only pay their round contribution.
              </motion.p>
            )}
          </AnimatePresence>
        </div>

        {/* Summary */}
        {isFormValid && contributionAmount !== null && (
          <div className="rounded-2xl p-3" style={glass.inner}>
            <p className="text-xs font-semibold mb-1.5" style={{ color: 'var(--muted)' }}>SUMMARY</p>
            <div className="space-y-1">
              {[
                ['Pot per round', `${formatUsdc(contributionAmount * BigInt(memberCount))} USDC`],
                ['Total rounds', memberCount.toString()],
                collateralOn && collateralAmount > 0n
                  ? ['Security deposit (locked at join)', `${formatUsdc(collateralAmount)} USDC`]
                  : ['Security deposit', 'None'],
                ['You pay today', collateralOn && collateralAmount > 0n ? `${formatUsdc(collateralAmount)} USDC` : '0 USDC'],
              ].map(([k, v]) => (
                <div key={String(k)} className="flex justify-between text-xs">
                  <span style={{ color: 'var(--subtle)' }}>{k}</span>
                  <span className="font-semibold tabular-nums" style={{ color: 'var(--ink)' }}>{v}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* CTA */}
        <AnimatePresence mode="wait">
          <motion.div key="ctas" className="space-y-2">
            {wrongChain ? (
              <button onClick={() => switchChain({ chainId: AJO_CHAIN_ID })} className="w-full rounded-2xl py-3.5 text-sm font-semibold text-white" style={{ background: '#d97706' }}>
                Switch to Arc Testnet
              </button>
            ) : isApproving ? (
              <div className="rounded-2xl p-3 text-center text-sm" style={glass.inner}>
                {isApprovePending ? 'Confirm approval in wallet...' : 'Confirming approval...'}
              </div>
            ) : isCreating ? (
              <div className="rounded-2xl p-3 text-center text-sm" style={glass.inner}>
                {isCreatePending ? 'Confirm in wallet...' : 'Creating circle on-chain...'}
              </div>
            ) : showCreateBtn ? (
              <button onClick={handleCreate} disabled={!isFormValid || isBusy} className="w-full rounded-2xl py-3.5 text-sm font-semibold text-white disabled:opacity-40" style={{ background: 'linear-gradient(135deg, #d97706 0%, #059669 100%)' }}>
                Create circle
              </button>
            ) : (
              <button onClick={handleApprove} disabled={!isFormValid || isBusy} className="w-full rounded-2xl py-3.5 text-sm font-semibold text-white disabled:opacity-40" style={{ background: 'linear-gradient(135deg, #d97706 0%, #059669 100%)' }}>
                Allow USDC &amp; Continue
              </button>
            )}
          </motion.div>
        </AnimatePresence>

        {!isBusy && approveTxHash && !isApproveSuccess && !isCreateSuccess && (
          <button onClick={handleReset} className="w-full text-center text-xs" style={{ color: 'var(--subtle)' }}>Try again</button>
        )}
      </motion.div>
    </div>
  );
}
