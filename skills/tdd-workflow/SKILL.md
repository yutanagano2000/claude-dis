---
name: tdd-workflow
description: Provides TDD workflow guidance, coverage targets, and test patterns for Vitest and React Testing Library. Use when writing tests, implementing new features with TDD, or checking test coverage requirements.
---

# TDD Workflow

## Cycle

```
Red (failing test) -> Green (minimal implementation) -> Refactor -> Repeat
```

## Coverage Targets (80%+ required)

| Metric | Minimum | Recommended |
|--------|---------|-------------|
| Statements | 80% | 90%+ |
| Branches | 80% | 85%+ |
| Functions | 80% | 85%+ |
| Lines | 80% | 90%+ |

## TDD Required For

- Utility functions (`lib/`, `utils/`) - pure functions
- Validation logic - many edge cases
- Calculations / transforms - clear I/O
- Custom hooks (logic part) - state transitions
- API route handlers - request/response
- Security features - auth, CSRF, rate limiting

## TDD Optional For

- UI component visuals, external library wrappers, prototype code, config files, auto-generated code (shadcn/ui)

## Test File Placement

```
src/lib/__tests__/utils.test.ts
src/app/[route]/__tests__/XxxView.test.tsx
src/app/[route]/_hooks/__tests__/useXxx.test.ts
src/__tests__/setup.ts
src/__tests__/mocks/handlers.ts
```

## Commands

```bash
npm run test:run                                    # Unit tests
npm run test:coverage                               # Coverage report
npm run test:e2e                                    # E2E (Playwright)
npm run test:run -- path/to/test.ts                 # Single file
```

## Test Patterns

See [test-patterns.md](test-patterns.md) for hook tests, API route tests, and coverage config.

## Anti-Patterns

- Testing implementation details -> test behavior
- Snapshot overuse -> intent unclear on change
- Test interdependence -> each test must be independent
- Excessive mocking -> integration tests also needed
- Skipping `waitFor` -> causes flaky tests
