import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'
import { nodePolyfills } from 'vite-plugin-node-polyfills'

export default defineConfig({
  plugins: [react(), nodePolyfills()],
  define: {
    // Bake the deployed contract address into the production build so it
    // works on public hosting without a .env file.
    'import.meta.env.VITE_AJO_ADDRESS': JSON.stringify(
      process.env.VITE_AJO_ADDRESS ?? '0x64822c48a4de920e74d16df88cb3b0b6924819d6'
    ),
    // Public URL for invite links — must be set to the deployed Vercel/Netlify URL.
    // Falls back to empty string in dev/preview; invite button then copies just "#circle/N"
    // which users can paste into the home-page "Join by ID" box.
    'import.meta.env.VITE_PUBLIC_URL': JSON.stringify(
      process.env.VITE_PUBLIC_URL ?? ''
    ),
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
    dedupe: ['react', 'react-dom'],
  },
  optimizeDeps: {
    include: [
      'react',
      'react-dom',
      'react-dom/client',
      'react/jsx-runtime',
      '@tanstack/react-query',
      'wagmi',
      'wagmi/chains',
      'wagmi/connectors',
      'viem',
      'viem/chains',
      'connectkit',
      'framer-motion',
      'lucide-react',
      'sonner',
      'clsx',
      'tailwind-merge',
      'vite-plugin-node-polyfills/shims/buffer',
      'vite-plugin-node-polyfills/shims/global',
      'vite-plugin-node-polyfills/shims/process',
    ],
  },
  server: {
    allowedHosts: true,
    cors: true,
  },
})
