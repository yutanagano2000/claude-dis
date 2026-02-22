---
name: refactoring
description: Provides Next.js/React refactoring patterns and file organization rules. Use when refactoring code, splitting large files, or organizing component structure. Includes hook separation, dialog extraction, and directory standards.
---

# Refactoring Patterns (Next.js / React)

## File Size Rules

| Lines | Status | Action |
|-------|--------|--------|
| ~200 | OK | None |
| 200-500 | Warning | Consider splitting |
| 500+ | Violation | Split immediately |

After editing, verify: `wc -l <file>` then `npx tsc --noEmit`

## Mandatory Patterns

| Rule | When Violated |
|------|--------------|
| Hook separation | Split into `useXxxData` (fetch) + `useXxxActions` (CRUD) |
| Dialog extraction | Extract dialogs >50 lines to separate file |
| useState limit | Group 10+ useState into custom hooks |
| Type externalization | Move to `_types.ts` |
| Constant externalization | Move to `_constants.ts` |
| Component extraction | Repeated UI elements become subcomponents |

## Standard Directory Structure

```
src/app/[route]/
├── page.tsx              # Entry point (~150-300 lines)
├── _types.ts             # Type definitions
├── _constants.ts         # Constants
├── _utils.ts             # Helper functions
├── _hooks/
│   ├── index.ts          # Exports
│   ├── useXxxData.ts     # Data fetch + state
│   └── useXxxActions.ts  # CRUD operations
└── _components/
    ├── index.ts          # Exports
    └── FeatureName/
        ├── FeatureTab.tsx
        └── FeatureDialog.tsx
```

## Hook & Dialog Templates

See [hook-patterns.md](hook-patterns.md) for useXxxData, useXxxActions, and Dialog component templates.

## Anti-Patterns

1. Direct fetch in page.tsx -> Move to hooks
2. Inline dialog >50 lines -> Extract to component
3. 10+ useState -> Group into hook
4. Duplicated fetch logic -> Centralize in useXxxData
5. Magic numbers/strings -> Extract to constants
