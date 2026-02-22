# Test Patterns Reference

## Custom Hook Test

```typescript
import { renderHook, act } from "@testing-library/react";

describe("useXxx", () => {
  beforeEach(() => { vi.clearAllMocks(); });

  it("initial state", () => {
    const { result } = renderHook(() => useXxx());
    expect(result.current.data).toEqual([]);
  });

  it("action execution", async () => {
    const { result } = renderHook(() => useXxx());
    await act(async () => { await result.current.action(); });
    expect(result.current.data).not.toEqual([]);
  });
});
```

## API Route Test

```typescript
let callCount = 0;
vi.mock("@/db", () => ({
  db: {
    select: vi.fn(() => ({
      from: vi.fn(() => {
        callCount++;
        return Promise.resolve(callCount === 1 ? mockData : []);
      }),
    })),
  },
}));

import { GET, POST } from "../route";

describe("API", () => {
  beforeEach(() => { callCount = 0; });

  it("GET returns data", async () => {
    const res = await GET();
    expect((await res.json()).length).toBeGreaterThan(0);
  });
});
```

## Coverage Exclusions (vitest.config.ts)

```typescript
coverage: {
  exclude: [
    "node_modules/**",
    "src/__tests__/**",
    "**/*.d.ts",
    "**/index.ts",
    "src/app/**/page.tsx",
    "src/app/**/layout.tsx",
    "src/components/ui/**",
  ],
}
```
