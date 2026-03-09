import { vi } from 'vitest'

// Global Piscina mock for all server tests.
// Prevents worker threads from spawning during tests, which would fail
// because the worker (contentWorker.ts) imports .js extensions that
// only resolve at runtime with the tsx loader.
vi.mock('piscina', () => {
  return {
    default: class MockPiscina {
      private handler: ((input: unknown) => unknown) | null = null
      private _loadPromise: Promise<void>
      constructor(opts: { filename: string }) {
        this.handler = null
        this._loadPromise = import(opts.filename).then(mod => {
          this.handler = mod.default
        })
      }
      async run(input: unknown) {
        await this._loadPromise
        return this.handler!(input)
      }
    },
  }
})
