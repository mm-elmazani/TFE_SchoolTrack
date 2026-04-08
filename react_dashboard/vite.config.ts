/// <reference types="vitest" />
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import path from 'path';

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/setupTests.ts'],
    globals: true,
    exclude: ['e2e/**', 'node_modules/**'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html', 'lcov'],
      include: ['src/**/*.{ts,tsx}'],
      exclude: [
        'src/components/ui/**',   // shadcn/ui : wrappers Radix, pas a tester
        'src/main.tsx',
        'src/App.tsx',            // template Vite inutilise
        'src/App.css',
        'src/routes/**',          // config routes, teste implicitement
        'src/vite-env.d.ts',
        'src/**/*.test.*',
        'src/test/**',
        'src/api/axios.ts',          // intercepteurs JWT — niveau integration
      ],
    },
  },
});
