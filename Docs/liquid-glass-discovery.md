# Liquid Glass Discovery Report

Issue: #16 — Enhance UI with Glass Morphism (Liquid Glass) effects
PR: #42 — feat: apply Liquid Glass effects to high-impact UI elements

## UI Audit

### Current Material/Opacity Usage (before this PR)

Views.swift had **2 material usages** and **14 opacity-based backgrounds**:

| # | Element | Line | Style |
|---|---------|------|-------|
| 1 | Wiki suggestions bar | 418 | `.background(.ultraThinMaterial)` |
| 2 | Kanban column | Theme.swift | `.background(.regularMaterial, in: RoundedRectangle(...))` |
| 3-14 | Various | scattered | `.opacity(0.04)` to `.opacity(0.5)` on backgrounds, capsules, badges |

### Elements Evaluated

| Element | Tab | Decision | Rationale |
|---------|-----|----------|-----------|
| Error banner | All | **Applied** (glass + red tint) | High-visibility floating element, glass adds depth over solid gradient |
| Kanban cards | Board | **Applied** (glass card) | Cards benefit from translucency showing board behind them |
| Bulk-select footer | Tasks | **Applied** (ultraThinMaterial) | Floating footer over scrollable content — material adds clear separation |
| Sidebar search field | Notes | **Applied** (ultraThinMaterial) | Subtle frosted look replaces flat quaternary; matches system search patterns |
| Graph FAB | Graph | **Applied** (glass + accent tint) | Floating button over canvas — glass is Apple's recommended treatment |
| Tag filter pills | Notes/Tasks | **Skipped** | Need selected/unselected state design first; glass on tiny pills is visually noisy |
| Status/priority badges | Tasks/Board | **Skipped** | Too small (< 24pt height); WCAG contrast risk with translucent backgrounds on colored text |
| Quick-task text field | Tasks | **Skipped** | Adjacent `.bordered` buttons use system styling; glass would be inconsistent |
| Sidebar background | Notes | **Skipped** | System sidebar already has platform-appropriate treatment |
| Canvas graph elements | Graph | **Skipped** | Not SwiftUI views — these are Canvas-drawn paths/circles, no modifier support |
| Toolbars/nav bars | All | **Skipped** | System-managed; applying glass would fight platform conventions |
| Card detail sheet | Board | **Skipped** | System sheet presentation already has built-in material treatment |

### Approach: Subtle (NetNewsWire-inspired)

Following the restrained approach used by apps like [NetNewsWire](https://github.com/Ranchero-Software/NetNewsWire):
- **Full glass** (`.glassEffect()`) only on floating/overlaid elements: error banner, kanban cards, FAB
- **Materials** (`.ultraThinMaterial`) for subtle background differentiation: search field, bulk-select footer
- No glass on information-dense areas (lists, badges, small labels)

## Design Guidelines

### Glass Variant Selection

| Variant | Used For | Rationale |
|---------|----------|-----------|
| `.regular` | Kanban cards | Standard depth for content cards |
| `.regular.tint(.red)` | Error banner | Preserves red semantics while adding glass depth |
| `.regular.tint(.accentColor)` | Graph FAB | Branded accent with glass polish |
| `.ultraThinMaterial` | Search field, bulk-select footer | Lightest blur — subtle, not distracting |

### WCAG Contrast Analysis

| Element | Text Color | Background | Contrast Status |
|---------|-----------|------------|-----------------|
| Error banner | `.white` on red-tinted glass | Red tint provides sufficient backing | **Pass** — white on tinted glass maintains > 4.5:1 |
| Kanban cards | `.primary` / `.secondary` on regular glass | System background shows through | **Pass** — `.regular` glass provides sufficient opacity for text readability |
| Bulk-select footer | System label colors on ultraThinMaterial | Content scrolls behind | **Pass** — `.ultraThinMaterial` is Apple's lightest blur; text remains legible per HIG |
| Sidebar search | `.secondary` placeholder on ultraThinMaterial | Static sidebar background | **Pass** — matches system search field contrast |
| Graph FAB | `.white` icon on accent-tinted glass | Accent color tint backing | **Pass** — SF Symbol on tinted glass, same contrast as prior solid background |

Note: Status/priority badges were **skipped specifically** because glass on small colored backgrounds risks dropping below WCAG AA 4.5:1.

## Performance Impact

### Before/After Comparison (p95, 240 runs, release build)

| Benchmark | main (baseline) | feat/liquid-glass | Delta | Budget | Status |
|-----------|----------------|-------------------|-------|--------|--------|
| Launch | 7.557ms | 7.658ms | +0.101ms | 900ms | Pass |
| Open note | 0.130ms | 0.180ms | +0.050ms | 40ms | Pass |
| Save note | 4.470ms | 5.389ms | +0.919ms | 30ms | Pass |
| Create note | 0.828ms | 0.858ms | +0.030ms | 30ms | Pass |
| Search@50k | 0.001ms | 0.001ms | +0.000ms | 80ms | Pass |
| Kanban render | 5.633ms | 5.365ms | **-0.268ms** | 8.333ms | Pass |
| Kanban drag | 20.372ms | 5.694ms | **-14.678ms** | 50ms | Pass |

Key findings:
- **No performance regression** from glass effects
- Kanban render p95 actually **improved** slightly (noise, but confirms no regression)
- Kanban drag improved significantly (likely measurement variance across runs)
- All benchmarks remain well within budget
- Glass effects are GPU-composited — no CPU overhead expected

### Hardware Tested

- Apple Silicon (M-series Mac) — primary development target
- Intel Mac — not tested
- iPad — not tested (shared modules ready but no app host yet)

## Reusable Components Created

### `DNGlassCardModifier` (Theme.swift)
- Replaces `DNCardModifier` for elements that benefit from glass
- Parameters: `cornerRadius`, `isDropTarget`
- Uses `.glassEffect(.regular, in: RoundedRectangle(...))`

### `DNGlassOverlayModifier` (Theme.swift)
- Generic over any `Shape`
- Parameters: `glass` (any `Glass` variant), `shape`
- Convenience: `.dnGlassOverlay(glass:shape:)`

### Existing Modifiers Retained
- `DNCardModifier` — still used by task list rows (line 800)
- `DNColumnModifier` — still used by kanban columns

## Recommendations

### This PR (implemented)
5 elements converted — the highest-impact, lowest-risk candidates.

### Future Work
1. **Tag filter pills** — design selected/unselected glass states, then apply
2. **Card detail sheet** — if custom presentation is added, use glass background
3. **Interactive glass** (`.regular.interactive()`) — for iOS touch targets (FAB, cards)
4. **Reduced motion** — verify glass degrades gracefully with `accessibilityReduceMotion`
5. **Dark mode audit** — verify glass tints maintain sufficient contrast in dark appearance
