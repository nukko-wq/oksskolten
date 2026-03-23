# Repository Guidelines

## Project Structure & Module Organization
`src/` contains the React 19 client: `components/` for UI, `pages/` for routed screens, `hooks/` for stateful client logic, `lib/` for reusable helpers, and `data/` for static UI metadata. `server/` contains the Fastify API, feed fetcher, chat adapters, and persistence layers such as `server/routes/`, `server/db/`, `server/fetcher/`, and `server/providers/`. `shared/` holds cross-runtime contracts like types, models, and URL helpers. Tests live beside implementation as `*.test.ts` or `*.test.tsx`; client test setup is in `src/__tests__/setup.ts`, server setup in `server/__tests__/setup.ts`.

## Build, Test, and Development Commands
Use `pnpm` for package management.

- `pnpm dev`: start the Vite client on `http://localhost:5173`.
- `pnpm dev:server`: run the Fastify server with file watching and `.env` loading.
- `pnpm dev:server:noauth`: same as above, but with auth disabled for local debugging.
- `pnpm build`: create the production Vite bundle.
- `pnpm lint`: run ESLint across `src/`, `server/`, and `shared/`.
- `pnpm typecheck`: run TypeScript without emitting files.
- `pnpm test`: run the full Vitest suite for both server and client.
- `pnpm test:watch`: run Vitest in watch mode during TDD.

## Coding Style & Naming Conventions
Write TypeScript with 2-space indentation and keep modules focused on one responsibility. Use `PascalCase` for React components, `use-*.ts` for hooks, and `kebab-case` for other file names such as `article-images.ts`. Prefer shared contracts in `shared/` over duplicating shapes. ESLint enforces `@typescript-eslint/no-floating-promises` and React Hooks rules; fix warnings before opening a PR.

## Testing Guidelines
Work in TDD order: explore, write a failing test, make it pass, then refactor. Server tests run in the `node` environment with in-memory DB settings; client tests run in `jsdom`. Name tests `*.test.ts` or `*.test.tsx` next to the code they verify. Run targeted suites with commands like `pnpm test -- server/fetcher/rss.test.ts` before a final `pnpm test`.

## Commit & Pull Request Guidelines
Recent history uses short, imperative subjects with prefixes such as `fix:`, `test:`, `docs:`, and `perf:`. Keep commits scoped to one concern. PRs should explain behavior changes, mention affected areas like `src/` or `server/fetcher/`, link issues when relevant, and attach screenshots for UI changes. Include the validation steps you ran, for example `pnpm lint && pnpm test`.

## Security & Configuration Tips
Keep secrets in `.env`; do not hardcode provider keys. Use `.env.example` as the source of truth for required variables. For local development with seeded data, default startup loads demo content unless `NO_SEED=1` is set.
