import { useState, useEffect } from 'react';
import { WalletButton } from '@/components/WalletButton';
import { motion, AnimatePresence } from 'framer-motion';
import { HomePage } from '@/components/HomePage';
import { CreateCircle } from '@/components/CreateCircle';
import { CirclePage } from '@/components/CirclePage';
import { MyCircles } from '@/components/MyCircles';

type View =
  | { page: 'home' }
  | { page: 'create' }
  | { page: 'circle'; id: bigint }
  | { page: 'my-circles' };

function parseHashRoute(): View {
  const hash = window.location.hash; // e.g. "#circle/2"
  // Match #circle/ or #/circle/ followed by digits, not immediately followed by more digits.
  const m = hash.match(/#\/?circle\/(\d+)(?!\d)/);
  const rawId = m ? m[1] : null;

  if (rawId !== null) {
    const n = BigInt(rawId);
    return { page: 'circle', id: n };
  }
  if (hash === '#create' || hash === '#/create') return { page: 'create' };
  if (hash === '#my-circles' || hash === '#/my-circles') return { page: 'my-circles' };
  return { page: 'home' };
}

function navigate(view: View) {
  if (view.page === 'home') window.location.hash = '';
  else if (view.page === 'create') window.location.hash = 'create';
  else if (view.page === 'my-circles') window.location.hash = 'my-circles';
  else if (view.page === 'circle') window.location.hash = `circle/${view.id.toString()}`;
}

export default function App() {
  const [view, setView] = useState<View>(parseHashRoute);

  useEffect(() => {
    function onHashChange() {
      setView(parseHashRoute());
    }
    window.addEventListener('hashchange', onHashChange);
    return () => window.removeEventListener('hashchange', onHashChange);
  }, []);

  function goTo(v: View) {
    navigate(v);
    setView(v);
  }

  return (
    <div
      className="relative min-h-dvh overflow-hidden"
      style={{ background: 'linear-gradient(180deg, #fffbf2 0%, #fef9ef 50%, #f0faf5 100%)' }}
    >
      {/* Ambient blobs — amber + green ajo palette */}
      <div className="fixed inset-0 pointer-events-none overflow-hidden">
        <div
          style={{
            position: 'absolute', top: '5%', left: '-5%',
            width: 340, height: 340, borderRadius: '50%',
            background: 'radial-gradient(circle, rgba(251,191,36,0.18) 0%, transparent 70%)',
            filter: 'blur(70px)',
          }}
        />
        <div
          style={{
            position: 'absolute', bottom: '10%', right: '-5%',
            width: 320, height: 320, borderRadius: '50%',
            background: 'radial-gradient(circle, rgba(16,185,129,0.15) 0%, transparent 70%)',
            filter: 'blur(65px)',
          }}
        />
        <div
          style={{
            position: 'absolute', top: '45%', right: '15%',
            width: 200, height: 200, borderRadius: '50%',
            background: 'radial-gradient(circle, rgba(245,158,11,0.12) 0%, transparent 70%)',
            filter: 'blur(50px)',
          }}
        />
      </div>

      {/* Header */}
      <header
        className="relative z-20 flex items-center justify-between px-4 py-4"
        style={{
          background: 'rgba(255,255,255,0.6)',
          backdropFilter: 'blur(20px)',
          borderBottom: '1px solid rgba(245,158,11,0.12)',
        }}
      >
        <button
          onClick={() => goTo({ page: 'home' })}
          className="display text-lg font-bold"
          style={{ color: '#92400e', letterSpacing: '-0.02em' }}
        >
          Ajo
          <span style={{ color: '#059669' }}>.</span>
        </button>
        <WalletButton />
      </header>

      {/* Main */}
      <main className="relative z-10 mx-auto max-w-md px-4 pb-12 pt-6">
        <AnimatePresence mode="wait">
          <motion.div
            key={view.page + (view.page === 'circle' ? view.id.toString() : '')}
            initial={{ opacity: 0, x: 10 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -10 }}
            transition={{ duration: 0.2 }}
          >
            {view.page === 'home' && (
              <HomePage
                onCreateCircle={() => goTo({ page: 'create' })}
                onMyCircles={() => goTo({ page: 'my-circles' })}
              />
            )}
            {view.page === 'create' && (
              <CreateCircle
                onBack={() => goTo({ page: 'home' })}
                onCreated={(id) => goTo({ page: 'circle', id })}
              />
            )}
            {view.page === 'circle' && (
              <CirclePage
                circleId={view.id}
                onBack={() => goTo({ page: 'my-circles' })}
              />
            )}
            {view.page === 'my-circles' && (
              <MyCircles
                onBack={() => goTo({ page: 'home' })}
                onCreateCircle={() => goTo({ page: 'create' })}
                onSelectCircle={(id) => goTo({ page: 'circle', id })}
              />
            )}
          </motion.div>
        </AnimatePresence>
      </main>
    </div>
  );
}
