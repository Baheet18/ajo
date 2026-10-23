import { useState, useEffect, useCallback, useRef } from 'react';
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useSwitchChain } from 'wagmi';
import { erc20Abi } from 'viem';
import { toast } from 'sonner';
import {
  ArrowLeft, Copy, Check, ExternalLink, Clock, ChevronDown, ChevronUp,
  Loader2, CircleDollarSign, AlertTriangle,
} from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { AJO_ADDRESS, AJO_ABI, AJO_CHAIN_ID, USDC_ADDRESS } from '@/lib/ajo-contract';
import { formatUsdc, shortAddr, formatCountdown } from '@/lib/format';
import { publicClient } from '@/lib/publicClient';

const ZERO_ADDR = '0x0000000000000000000000000000000000000000';
const LOAD_TIMEOUT_MS = 10_000;

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

interface PayoutHistoryItem {
  round: number;
  recipient: string;
  amount: bigint;
  txHash: string;
}

interface CircleData {
  name: string;
  creator: string;
  contributionAmount: bigint;
  memberCount: number;
  roundDuration: bigint;
  status: number;
  currentRound: number;
  roundDeadline: bigint;
  members: readonly string[];
  payoutRecipients: readonly string[];
  defaulted: readonly boolean[];
}

interface CirclePageProps {
  circleId: bigint;
  onBack: () => void;
}

export function CirclePage({ circleId, onBack }: CirclePageProps) {
  const { address, chainId } = useAccount();
  const { switchChain } = useSwitchChain();
  const wrongChain = !!chainId && chainId !== AJO_CHAIN_ID;

  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  const [shareLink, setShareLink] = useState('');
  const [copied, setCopied] = useState(false);
  const [payoutHistory] = useState<PayoutHistoryItem[]>([]);
  const [showHistory, setShowHistory] = useState(false);

  // Read state
  const [circle, setCircle] = useState<CircleData | null>(null);
  const [paidStatus, setPaidStatus] = useState<readonly boolean[] | null>(null);
  const [nextRecipient, setNextRecipient] = useState<string | null>(null);
  const [potSize, setPotSize] = useState<bigint | null>(null);
  const [pendingWithdrawal, setPendingWithdrawal] = useState<bigint | null>(null);
  const [allowance, setAllowance] = useState<bigint | null>(null);
  const [isMember, setIsMember] = useState<boolean>(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const t = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1000);
    return () => clearInterval(t);
  }, []);

  useEffect(() => {
    // Use the baked-in public URL so invite links work outside the Arc Studio preview.
    const base = (import.meta.env.VITE_PUBLIC_URL as string) || location.origin;
    setShareLink(`${base}#circle/${Number(circleId)}`);
  }, [circleId]);

  // Single fetch function using publicClient directly — bypasses wallet chain
  const fetchData = useCallback(async () => {
    console.log('[CirclePage] fetchData start', { circleId: circleId.toString(), address });
    setIsLoading(true);
    setLoadError(null);
    try {
      // Validate the ID first — contract uses 1-based IDs (++circleCount), so 0 is never valid
      // and any ID > circleCount does not exist.
      const count = await publicClient.readContract({
        address: AJO_ADDRESS,
        abi: AJO_ABI,
        functionName: 'circleCount',
      });
      console.log('[CirclePage] circleCount', count.toString(), 'requested id', circleId.toString());
      if (circleId === 0n || circleId > count) {
        const msg = `Circle #${circleId.toString()} does not exist. Valid IDs: 1–${count.toString()}.`;
        console.error('[CirclePage] invalid circleId', { href: window.location.href, hash: window.location.hash, id: circleId.toString(), count: count.toString() });
        setLoadError(`NOT_FOUND:${msg}`);
        setIsLoading(false);
        hasDataRef.current = true; // stop timeout
        return;
      }

      // Core circle data — always needed
      const rawCircle = await publicClient.readContract({
        address: AJO_ADDRESS,
        abi: AJO_ABI,
        functionName: 'getCircle',
        args: [circleId],
      });
      console.log('[CirclePage] getCircle ok', rawCircle);

      const c = rawCircle as {
        name: string; creator: string; contributionAmount: bigint;
        memberCount: bigint | number; roundDuration: bigint; status: bigint | number;
        currentRound: bigint | number; roundDeadline: bigint;
        members: readonly string[]; payoutRecipients: readonly string[];
        defaulted: readonly boolean[];
      };
      const circleData: CircleData = {
        name: c.name,
        creator: c.creator,
        contributionAmount: c.contributionAmount,
        memberCount: Number(c.memberCount),
        roundDuration: c.roundDuration,
        status: Number(c.status),
        currentRound: Number(c.currentRound),
        roundDeadline: c.roundDeadline,
        members: c.members,
        payoutRecipients: c.payoutRecipients,
        defaulted: c.defaulted,
      };
      setCircle(circleData);
      hasDataRef.current = true;

      // Parallel reads that depend on circle data
      const parallelReads: Promise<void>[] = [];

      // Paid status
      if (circleData.currentRound > 0) {
        parallelReads.push(
          publicClient.readContract({
            address: AJO_ADDRESS,
            abi: AJO_ABI,
            functionName: 'getRoundPaidStatus',
            args: [circleId, circleData.currentRound],
          }).then((v) => {
            console.log('[CirclePage] getRoundPaidStatus ok', v);
            setPaidStatus(v);
          }).catch((e) => console.warn('[CirclePage] getRoundPaidStatus failed', e))
        );
      }

      // Next recipient
      parallelReads.push(
        publicClient.readContract({
          address: AJO_ADDRESS,
          abi: AJO_ABI,
          functionName: 'getNextRecipient',
          args: [circleId],
        }).then((v) => {
          console.log('[CirclePage] getNextRecipient ok', v);
          setNextRecipient(v);
        }).catch((e) => console.warn('[CirclePage] getNextRecipient failed', e))
      );

      // Pot size
      parallelReads.push(
        publicClient.readContract({
          address: AJO_ADDRESS,
          abi: AJO_ABI,
          functionName: 'getPotSize',
          args: [circleId],
        }).then((v) => {
          console.log('[CirclePage] getPotSize ok', v);
          setPotSize(v);
        }).catch((e) => console.warn('[CirclePage] getPotSize failed', e))
      );

      // Wallet-specific reads (only if connected)
      if (address) {
        parallelReads.push(
          publicClient.readContract({
            address: AJO_ADDRESS,
            abi: AJO_ABI,
            functionName: 'pendingWithdrawals',
            args: [address],
          }).then((v) => {
            console.log('[CirclePage] pendingWithdrawals ok', v);
            setPendingWithdrawal(v);
          }).catch((e) => console.warn('[CirclePage] pendingWithdrawals failed', e))
        );

        parallelReads.push(
          publicClient.readContract({
            address: USDC_ADDRESS,
            abi: erc20Abi,
            functionName: 'allowance',
            args: [address, AJO_ADDRESS],
          }).then((v) => {
            console.log('[CirclePage] allowance ok', v);
            setAllowance(v);
          }).catch((e) => console.warn('[CirclePage] allowance failed', e))
        );

        parallelReads.push(
          publicClient.readContract({
            address: AJO_ADDRESS,
            abi: AJO_ABI,
            functionName: 'isMember',
            args: [circleId, address],
          }).then((v) => {
            console.log('[CirclePage] isMember ok', v);
            setIsMember(v);
          }).catch((e) => console.warn('[CirclePage] isMember failed', e))
        );
      }

      await Promise.all(parallelReads);
      setLoadError(null);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error('[CirclePage] fetchData failed', e);
      setLoadError(msg);
    } finally {
      setIsLoading(false);
    }
  }, [circleId, address]);

  // Timeout guard — show error if initial load takes too long.
  // We use a ref to track whether we already have data so the timeout
  // callback does not call setState after unmount or after data arrived.
  const hasDataRef = useRef(false);
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => {
    // Reset on circleId change (start fresh)
    hasDataRef.current = false;
    if (timeoutRef.current) clearTimeout(timeoutRef.current);
    timeoutRef.current = setTimeout(() => {
      if (!hasDataRef.current) {
        const msg = `Timed out loading circle ${circleId.toString()} from ${AJO_ADDRESS} via https://rpc.testnet.arc.io`;
        console.error('[CirclePage] timeout', msg);
        setLoadError(msg);
        setIsLoading(false);
      }
    }, LOAD_TIMEOUT_MS);
    void fetchData();
    return () => { if (timeoutRef.current) clearTimeout(timeoutRef.current); };
    // fetchData is stable per circleId/address via useCallback
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [circleId, address]);

  const refetchAll = useCallback(() => { void fetchData(); }, [fetchData]);

  // Approve
  const { writeContract: writeApprove, data: approveTxHash, isPending: isApprovePending } = useWriteContract();
  const { isLoading: isApproveConfirming, isSuccess: isApproveSuccess } = useWaitForTransactionReceipt({ hash: approveTxHash });
  const prevApproveRef = useRef(false);
  if (isApproveSuccess && !prevApproveRef.current) { prevApproveRef.current = true; toast.success('Approval confirmed'); refetchAll(); }
  if (!isApproveSuccess) prevApproveRef.current = false;

  // Join
  const { writeContract: writeJoin, data: joinTxHash, isPending: isJoinPending } = useWriteContract();
  const { isLoading: isJoinConfirming, isSuccess: isJoinSuccess } = useWaitForTransactionReceipt({ hash: joinTxHash });
  const prevJoinRef = useRef(false);
  if (isJoinSuccess && !prevJoinRef.current) { prevJoinRef.current = true; toast.success('Joined!'); refetchAll(); }
  if (!isJoinSuccess) prevJoinRef.current = false;

  // Contribute
  const { writeContract: writeContribute, data: contributeTxHash, isPending: isContributePending } = useWriteContract();
  const { isLoading: isContributeConfirming, isSuccess: isContributeSuccess } = useWaitForTransactionReceipt({ hash: contributeTxHash });
  const prevContributeRef = useRef(false);
  if (isContributeSuccess && !prevContributeRef.current) { prevContributeRef.current = true; toast.success('Contribution sent!'); refetchAll(); }
  if (!isContributeSuccess) prevContributeRef.current = false;

  // Payout
  const { writeContract: writePayout, data: payoutTxHash, isPending: isPayoutPending } = useWriteContract();
  const { isLoading: isPayoutConfirming, isSuccess: isPayoutSuccess } = useWaitForTransactionReceipt({ hash: payoutTxHash });
  const prevPayoutRef = useRef(false);
  if (isPayoutSuccess && !prevPayoutRef.current) { prevPayoutRef.current = true; toast.success('Payout triggered!'); refetchAll(); }
  if (!isPayoutSuccess) prevPayoutRef.current = false;

  // Withdraw
  const { writeContract: writeWithdraw, data: withdrawTxHash, isPending: isWithdrawPending } = useWriteContract();
  const { isLoading: isWithdrawConfirming, isSuccess: isWithdrawSuccess } = useWaitForTransactionReceipt({ hash: withdrawTxHash });
  const prevWithdrawRef = useRef(false);
  if (isWithdrawSuccess && !prevWithdrawRef.current) { prevWithdrawRef.current = true; toast.success('Funds withdrawn!'); refetchAll(); }
  if (!isWithdrawSuccess) prevWithdrawRef.current = false;

  // Loading state
  if (isLoading && circle === null) {
    return (
      <div className="flex flex-col items-center justify-center py-16 space-y-3">
        <Loader2 className="size-8 animate-spin" style={{ color: '#d97706' }} />
        <p className="text-sm" style={{ color: 'var(--muted)' }}>Loading circle...</p>
      </div>
    );
  }

  // Error state — distinguish "not found" from a real RPC error
  if (loadError && circle === null) {
    const isNotFound = loadError.startsWith('NOT_FOUND:');
    const displayMsg = isNotFound ? loadError.replace('NOT_FOUND:', '') : loadError;
    return (
      <div className="flex flex-col items-center justify-center py-16 space-y-4 px-4">
        <AlertTriangle className="size-10" style={{ color: isNotFound ? '#6b7280' : '#d97706' }} />
        <div className="text-center space-y-1">
          <p className="text-sm font-semibold" style={{ color: 'var(--ink)' }}>
            {isNotFound ? 'Circle not found' : 'Could not load circle'}
          </p>
          <p className="text-xs break-all max-w-xs" style={{ color: 'var(--muted)' }}>{displayMsg}</p>
        </div>
        {!isNotFound && (
          <button
            onClick={() => { setIsLoading(true); setLoadError(null); void fetchData(); }}
            className="rounded-2xl px-5 py-2.5 text-sm font-semibold text-white"
            style={{ background: '#d97706' }}
          >
            Retry
          </button>
        )}
        <button onClick={onBack} className="text-xs" style={{ color: 'var(--subtle)' }}>Go back</button>
      </div>
    );
  }

  if (!circle) return null;

  const status = circle.status;
  const members = circle.members;
  const payoutRecipients = circle.payoutRecipients;
  const deadlineSecs = Number(circle.roundDeadline);
  const secondsLeft = deadlineSecs > 0 ? deadlineSecs - now : 0;
  const pastDeadline = deadlineSecs > 0 && now >= deadlineSecs;
  const isActive = status === 1;
  const isPending = status === 0;
  const isEnded = status === 2;
  const currentRound = circle.currentRound;
  const memberCount = circle.memberCount;

  const userIndex = members.findIndex((m) => m.toLowerCase() === address?.toLowerCase());
  const userHasPaid = paidStatus && userIndex >= 0 ? paidStatus[userIndex] : false;
  const needsApproval =
    circle.contributionAmount > 0n &&
    (allowance == null || allowance < circle.contributionAmount);

  const explorerBase = 'https://explorer.testnet.arc.io';

  // Transaction handlers — prompt chain switch only here
  function ensureChain(fn: () => void) {
    if (wrongChain) { switchChain({ chainId: AJO_CHAIN_ID }); return; }
    fn();
  }

  function handleApprove() {
    ensureChain(() => writeApprove({
      address: USDC_ADDRESS,
      abi: erc20Abi,
      functionName: 'approve',
      args: [AJO_ADDRESS, circle!.contributionAmount * BigInt(memberCount + 5)],
      chainId: AJO_CHAIN_ID,
    }));
  }

  function handleJoin() {
    ensureChain(() => {
      if (needsApproval) { handleApprove(); return; }
      writeJoin({ address: AJO_ADDRESS, abi: AJO_ABI, functionName: 'join', args: [circleId], chainId: AJO_CHAIN_ID });
    });
  }

  function handleContribute() {
    ensureChain(() => {
      if (needsApproval) { handleApprove(); return; }
      writeContribute({ address: AJO_ADDRESS, abi: AJO_ABI, functionName: 'contribute', args: [circleId], chainId: AJO_CHAIN_ID });
    });
  }

  function handlePayout() {
    ensureChain(() => writePayout({
      address: AJO_ADDRESS, abi: AJO_ABI, functionName: 'payout', args: [circleId], chainId: AJO_CHAIN_ID,
    }));
  }

  function handleWithdraw() {
    ensureChain(() => writeWithdraw({
      address: AJO_ADDRESS, abi: AJO_ABI, functionName: 'withdraw', args: [], chainId: AJO_CHAIN_ID,
    }));
  }

  const isBusy =
    isApprovePending || isApproveConfirming ||
    isJoinPending || isJoinConfirming ||
    isContributePending || isContributeConfirming ||
    isPayoutPending || isPayoutConfirming ||
    isWithdrawPending || isWithdrawConfirming;

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center gap-3">
        <button onClick={onBack} className="flex size-9 items-center justify-center rounded-xl" style={glass.inner}>
          <ArrowLeft className="size-4" style={{ color: 'var(--ink)' }} />
        </button>
        <div className="flex-1 min-w-0">
          <h2 className="display truncate text-xl font-bold" style={{ color: 'var(--ink)', letterSpacing: '-0.02em' }}>
            {circle.name}
          </h2>
          <p className="text-xs" style={{ color: 'var(--muted)' }}>Circle #{circleId.toString()}</p>
        </div>
        <button
          onClick={() => {
            void navigator.clipboard.writeText(shareLink).then(() => {
              setCopied(true);
              setTimeout(() => setCopied(false), 2000);
            });
          }}
          className="flex items-center gap-1.5 rounded-xl px-3 py-2 text-xs font-semibold"
          style={glass.inner}
        >
          {copied ? <Check className="size-3" style={{ color: '#059669' }} /> : <Copy className="size-3" />}
          Invite
        </button>
      </div>

      {/* Status + pot hero */}
      <motion.section
        className="rounded-3xl p-5"
        style={glass.card}
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
      >
        <div className="flex items-center justify-between mb-3">
          <span
            className="rounded-full px-2.5 py-1 text-xs font-semibold"
            style={{ background: `${STATUS_COLORS[status]}18`, color: STATUS_COLORS[status] }}
          >
            {STATUS_LABELS[status]}
          </span>
          {isActive && (
            <span className="flex items-center gap-1.5 text-xs" style={{ color: 'var(--muted)' }}>
              <Clock className="size-3" />
              Round {currentRound}/{memberCount}
            </span>
          )}
        </div>

        <div className="mb-4 space-y-2">
          <p className="text-xs font-semibold mb-1" style={{ color: 'var(--muted)' }}>CURRENT POT</p>
          <div className="flex items-baseline gap-1.5">
            <span className="display text-4xl font-bold tabular-nums" style={{ color: 'var(--ink)', letterSpacing: '-0.03em' }}>
              {potSize != null ? formatUsdc(potSize) : '—'}
            </span>
            <span className="text-lg font-medium" style={{ color: 'var(--subtle)' }}>USDC</span>
          </div>
          {isActive && (
            <p className="mt-0.5 text-xs" style={{ color: 'var(--muted)' }}>
              Target: {formatUsdc(circle.contributionAmount * BigInt(members.length))} USDC
            </p>
          )}
          {/* Circle settings row — contribution + collateral */}
          <div className="flex items-center gap-2 flex-wrap pt-1">
            <span className="rounded-full px-2.5 py-1 text-xs font-semibold" style={{ background: 'rgba(217,119,6,0.1)', color: '#92400e' }}>
              {formatUsdc(circle.contributionAmount)} USDC/round
            </span>
            <span className="rounded-full px-2.5 py-1 text-xs font-semibold" style={{ background: 'rgba(18,45,69,0.06)', color: 'var(--muted)' }}>
              {circle.contributionAmount > 0n
                ? `${formatUsdc(circle.contributionAmount)} USDC deposit`
                : 'No collateral'}
            </span>
          </div>
        </div>

        {isActive && deadlineSecs > 0 && (
          <div
            className="rounded-2xl p-3 flex items-center gap-3"
            style={{ ...glass.inner, borderColor: pastDeadline ? 'rgba(186,43,76,0.2)' : 'rgba(255,255,255,0.56)' }}
          >
            <Clock className="size-4 shrink-0" style={{ color: pastDeadline ? '#ba2b4c' : '#d97706' }} />
            <div className="flex-1 min-w-0">
              <p className="text-xs font-semibold tabular-nums" style={{ color: pastDeadline ? '#ba2b4c' : 'var(--ink)' }}>
                {pastDeadline ? 'Deadline passed' : formatCountdown(secondsLeft)}
              </p>
              <p className="text-xs" style={{ color: 'var(--subtle)' }}>
                {pastDeadline ? 'Payout can be triggered now' : 'until payout opens early'}
              </p>
            </div>
          </div>
        )}
      </motion.section>

      {/* Pending withdrawal banner */}
      {pendingWithdrawal != null && pendingWithdrawal > 0n && (
        <motion.div
          className="rounded-2xl p-4 flex items-center justify-between"
          style={{ ...glass.card, borderColor: 'rgba(5,150,105,0.3)' }}
          initial={{ opacity: 0, scale: 0.97 }}
          animate={{ opacity: 1, scale: 1 }}
        >
          <div>
            <p className="text-xs font-semibold" style={{ color: '#059669' }}>FUNDS AVAILABLE</p>
            <p className="display text-xl font-bold tabular-nums" style={{ color: 'var(--ink)' }}>
              {formatUsdc(pendingWithdrawal)} USDC
            </p>
          </div>
          <button
            onClick={handleWithdraw}
            disabled={isBusy}
            className="rounded-2xl px-5 py-2.5 text-sm font-semibold text-white disabled:opacity-40"
            style={{ background: '#059669' }}
          >
            {isWithdrawPending ? 'Confirm...' : isWithdrawConfirming ? 'Withdrawing...' : 'Withdraw'}
          </button>
        </motion.div>
      )}

      {/* Wrong chain notice — shown only when wallet is connected to wrong chain */}
      {wrongChain && address && (
        <div
          className="rounded-2xl p-3 flex items-center gap-3"
          style={{ background: 'rgba(217,119,6,0.08)', border: '1px solid rgba(217,119,6,0.2)' }}
        >
          <AlertTriangle className="size-4 shrink-0" style={{ color: '#d97706' }} />
          <p className="text-xs flex-1" style={{ color: '#92400e' }}>
            Your wallet is on a different network. Switch to Arc Testnet to send transactions.
          </p>
          <button
            onClick={() => switchChain({ chainId: AJO_CHAIN_ID })}
            className="rounded-xl px-3 py-1.5 text-xs font-semibold text-white shrink-0"
            style={{ background: '#d97706' }}
          >
            Switch
          </button>
        </div>
      )}

      {/* Members */}
      <motion.section
        className="rounded-3xl p-5"
        style={glass.card}
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.05 }}
      >
        <div className="flex items-center justify-between mb-3">
          <p className="text-xs font-semibold" style={{ color: 'var(--muted)' }}>MEMBERS</p>
          <span className="text-xs" style={{ color: 'var(--subtle)' }}>{members.length}/{memberCount}</span>
        </div>
        <div className="space-y-2">
          {members.map((member, i) => {
            const isMe = member.toLowerCase() === address?.toLowerCase();
            const paid = paidStatus ? paidStatus[i] : false;
            const isNextRcpt =
              nextRecipient != null &&
              nextRecipient.toLowerCase() !== ZERO_ADDR &&
              member.toLowerCase() === nextRecipient.toLowerCase();
            const payoutPos = payoutRecipients.findIndex(
              (r) => r.toLowerCase() === member.toLowerCase()
            );

            return (
              <div
                key={member}
                className="flex items-center gap-3 rounded-2xl p-3"
                style={{
                  ...glass.inner,
                  borderColor: isNextRcpt ? 'rgba(217,119,6,0.35)' : 'rgba(255,255,255,0.56)',
                  background: isNextRcpt ? 'rgba(245,158,11,0.06)' : undefined,
                }}
              >
                <div
                  className="flex size-8 shrink-0 items-center justify-center rounded-full text-xs font-bold text-white"
                  style={{ background: isNextRcpt ? '#d97706' : '#94a3b8' }}
                >
                  {i + 1}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-xs font-semibold truncate" style={{ color: 'var(--ink)' }}>
                    {shortAddr(member)}{isMe ? ' (you)' : ''}
                  </p>
                  <p className="text-xs" style={{ color: 'var(--subtle)' }}>
                    Payout slot #{payoutPos + 1}
                    {isNextRcpt ? ' · Next to receive' : ''}
                  </p>
                </div>
                {isActive && (
                  <span
                    className="rounded-full px-2 py-0.5 text-xs font-semibold"
                    style={{
                      background: paid ? 'rgba(5,150,105,0.12)' : 'rgba(18,45,69,0.06)',
                      color: paid ? '#059669' : 'var(--subtle)',
                    }}
                  >
                    {paid ? 'Paid' : 'Unpaid'}
                  </span>
                )}
                {isNextRcpt && isActive && (
                  <CircleDollarSign className="size-4 shrink-0" style={{ color: '#d97706' }} />
                )}
              </div>
            );
          })}
          {isPending && members.length < memberCount && (
            <div className="rounded-2xl p-3 text-center" style={glass.inner}>
              <p className="text-xs" style={{ color: 'var(--subtle)' }}>
                Waiting for {memberCount - members.length} more member{memberCount - members.length !== 1 ? 's' : ''}...
              </p>
            </div>
          )}
        </div>
      </motion.section>

      {/* Payout order */}
      {payoutRecipients.length > 0 && (
        <motion.section
          className="rounded-3xl p-5"
          style={glass.card}
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.08 }}
        >
          <p className="mb-3 text-xs font-semibold" style={{ color: 'var(--muted)' }}>PAYOUT ORDER</p>
          <div className="flex flex-col gap-1.5">
            {payoutRecipients.map((recipient, i) => {
              const isNextRound = isActive && currentRound - 1 === i;
              const isPastRound = isActive && currentRound - 1 > i;
              const isMe = recipient.toLowerCase() === address?.toLowerCase();
              return (
                <div key={`${recipient}-${i}`} className="flex items-center gap-2.5">
                  <span
                    className="flex size-6 shrink-0 items-center justify-center rounded-full text-xs font-bold"
                    style={{
                      background: isPastRound ? '#059669' : isNextRound ? '#d97706' : 'rgba(18,45,69,0.08)',
                      color: isPastRound || isNextRound ? 'white' : 'var(--muted)',
                    }}
                  >
                    {isPastRound ? <Check className="size-3" /> : i + 1}
                  </span>
                  <span className="text-xs" style={{ color: isPastRound ? 'var(--subtle)' : 'var(--ink)', textDecoration: isPastRound ? 'line-through' : undefined }}>
                    {shortAddr(recipient)}{isMe ? ' (you)' : ''}
                  </span>
                  {isNextRound && (
                    <span className="rounded-full px-2 py-0.5 text-xs font-semibold" style={{ background: 'rgba(217,119,6,0.12)', color: '#d97706' }}>
                      Next
                    </span>
                  )}
                </div>
              );
            })}
          </div>
        </motion.section>
      )}

      {/* Action buttons */}
      {!isEnded && address && (
        <motion.section
          className="space-y-2"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.1 }}
        >
          {!wrongChain && isPending && !isMember && (
            <>
              {/* Join summary — shown before the member signs */}
              <div className="rounded-2xl p-3 space-y-1.5" style={{ background: 'rgba(217,119,6,0.06)', border: '1px solid rgba(217,119,6,0.18)' }}>
                <p className="text-xs font-semibold" style={{ color: '#92400e' }}>WHAT YOU'RE SIGNING</p>
                <div className="space-y-1">
                  <div className="flex justify-between text-xs">
                    <span style={{ color: 'var(--subtle)' }}>Security deposit (locked now)</span>
                    <span className="font-semibold tabular-nums" style={{ color: 'var(--ink)' }}>
                      {circle.contributionAmount > 0n ? `${formatUsdc(circle.contributionAmount)} USDC` : 'None'}
                    </span>
                  </div>
                  <div className="flex justify-between text-xs">
                    <span style={{ color: 'var(--subtle)' }}>Per-round contribution</span>
                    <span className="font-semibold tabular-nums" style={{ color: 'var(--ink)' }}>
                      {formatUsdc(circle.contributionAmount)} USDC × {circle.memberCount} rounds
                    </span>
                  </div>
                  <div className="flex justify-between text-xs border-t pt-1" style={{ borderColor: 'rgba(217,119,6,0.15)' }}>
                    <span className="font-semibold" style={{ color: '#92400e' }}>You lock today</span>
                    <span className="font-bold tabular-nums" style={{ color: '#92400e' }}>
                      {formatUsdc(circle.contributionAmount)} USDC
                    </span>
                  </div>
                </div>
                <p className="text-xs" style={{ color: 'var(--muted)' }}>
                  Deposit is refunded when the cycle ends if you don't miss any round.
                </p>
              </div>
            <button
              onClick={handleJoin}
              disabled={isBusy}
              className="w-full rounded-2xl py-3.5 text-sm font-semibold text-white disabled:opacity-40"
              style={{ background: 'linear-gradient(135deg, #d97706 0%, #059669 100%)' }}
            >
              {isJoinPending ? 'Confirm in wallet...' : isJoinConfirming ? 'Joining...' : needsApproval ? 'Allow USDC & Join' : 'Join circle'}
            </button>
            </>
          )}

          {wrongChain && isPending && !isMember && (
            <button
              onClick={handleJoin}
              className="w-full rounded-2xl py-3.5 text-sm font-semibold text-white"
              style={{ background: 'linear-gradient(135deg, #d97706 0%, #059669 100%)' }}
            >
              Switch network & Join
            </button>
          )}

          {!wrongChain && isActive && isMember && !userHasPaid && (
            <button
              onClick={handleContribute}
              disabled={isBusy}
              className="w-full rounded-2xl py-3.5 text-sm font-semibold text-white disabled:opacity-40"
              style={{ background: 'linear-gradient(135deg, #d97706 0%, #059669 100%)' }}
            >
              {isContributePending ? 'Confirm in wallet...' :
                isContributeConfirming ? 'Confirming...' :
                needsApproval ? 'Allow USDC & Contribute' :
                `Contribute ${formatUsdc(circle.contributionAmount)} USDC`}
            </button>
          )}

          {wrongChain && isActive && isMember && !userHasPaid && (
            <button
              onClick={handleContribute}
              className="w-full rounded-2xl py-3.5 text-sm font-semibold text-white"
              style={{ background: 'linear-gradient(135deg, #d97706 0%, #059669 100%)' }}
            >
              Switch network & Contribute
            </button>
          )}

          {isActive && isMember && userHasPaid && (
            <div className="rounded-2xl p-3 text-center" style={glass.inner}>
              <p className="text-sm font-semibold" style={{ color: '#059669' }}>Contribution submitted for this round</p>
            </div>
          )}

          {isActive && (
            <button
              onClick={handlePayout}
              disabled={isBusy || (!pastDeadline && !wrongChain)}
              className="w-full rounded-2xl py-3 text-sm font-semibold disabled:opacity-40"
              style={{ background: 'rgba(255,255,255,0.6)', border: '1px solid rgba(18,45,69,0.12)', color: 'var(--ink)' }}
            >
              {isPayoutPending ? 'Confirm in wallet...' :
                isPayoutConfirming ? 'Triggering payout...' :
                wrongChain ? 'Switch network & Trigger payout' :
                !pastDeadline ? 'Payout (opens after deadline)' :
                'Trigger payout'}
            </button>
          )}

          {isActive && needsApproval && !wrongChain && (
            <button
              onClick={handleApprove}
              disabled={isBusy}
              className="w-full rounded-2xl py-2.5 text-xs font-semibold disabled:opacity-40"
              style={{ background: 'rgba(217,119,6,0.1)', color: '#d97706', border: '1px solid rgba(217,119,6,0.2)' }}
            >
              {isApprovePending ? 'Confirm approval...' : isApproveConfirming ? 'Confirming...' : 'Allow USDC first'}
            </button>
          )}
        </motion.section>
      )}

      {/* Payout history */}
      {payoutHistory.length > 0 && (
        <motion.section className="rounded-3xl p-5" style={glass.card} initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
          <button onClick={() => setShowHistory((h) => !h)} className="flex w-full items-center justify-between">
            <p className="text-xs font-semibold" style={{ color: 'var(--muted)' }}>PAYOUT HISTORY</p>
            {showHistory ? <ChevronUp className="size-4" style={{ color: 'var(--subtle)' }} /> : <ChevronDown className="size-4" style={{ color: 'var(--subtle)' }} />}
          </button>
          <AnimatePresence>
            {showHistory && (
              <motion.div className="mt-3 space-y-2" initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} exit={{ opacity: 0, height: 0 }}>
                {payoutHistory.map((item) => (
                  <div key={`${item.round}-${item.txHash}`} className="flex items-center gap-3 rounded-2xl p-3" style={glass.inner}>
                    <span className="flex size-7 shrink-0 items-center justify-center rounded-full text-xs font-bold text-white" style={{ background: '#059669' }}>
                      {item.round}
                    </span>
                    <div className="flex-1 min-w-0">
                      <p className="text-xs font-semibold" style={{ color: 'var(--ink)' }}>
                        {shortAddr(item.recipient)} · {formatUsdc(item.amount)} USDC
                      </p>
                      <p className="text-xs" style={{ color: 'var(--subtle)' }}>Round {item.round}</p>
                    </div>
                    <a href={`${explorerBase}/tx/${item.txHash}`} target="_blank" rel="noreferrer" className="shrink-0">
                      <ExternalLink className="size-3.5" style={{ color: 'var(--subtle)' }} />
                    </a>
                  </div>
                ))}
              </motion.div>
            )}
          </AnimatePresence>
        </motion.section>
      )}
    </div>
  );
}
