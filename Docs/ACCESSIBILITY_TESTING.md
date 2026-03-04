# Accessibility Testing Guide

Guidelines and checklist for ensuring the NotesEngine app meets accessibility standards (WCAG AA) and provides an excellent experience for users with disabilities.

## Overview

Accessibility is a first-class requirement, not an afterthought. Before any PR affecting UI is merged, accessibility testing must be completed and documented.

## Testing Checklist for Pull Requests

### Pre-Flight Checks

- [ ] **Dynamic Type** (font scaling): Text responds to system font size changes (Control Center > Accessibility > Display & Text Size)
- [ ] **Color contrast** (WCAG AA): All text passes contrast ratio checks (≥4.5:1 for normal text, ≥3:1 for large text)
- [ ] **Voice Over** (screen reader): All interactive elements are announced correctly
- [ ] **Voice Control**: All actions accessible via voice commands
- [ ] **High Contrast Mode**: UI remains legible with increased contrast (macOS: System Preferences > Accessibility > Display > Increase contrast)
- [ ] **Zoom**: Interface remains functional at 200% zoom
- [ ] **Touch targets**: Interactive elements are ≥44x44 points (iOS) or ≥48x48 points (macOS recommended)

### Testing Procedures

See sections below for detailed testing steps per feature area.

## Color Contrast (WCAG AA)

### Requirement

All text and interactive elements must meet **WCAG AA** contrast ratios:

| Category | Contrast Ratio | Size |
|----------|---|---|
| Normal text | ≥4.5:1 | Any |
| Large text | ≥3:1 | 18pt+ or 14pt bold+ |
| UI components | ≥3:1 | (e.g., borders, icons) |
| Graphical elements | ≥3:1 | (e.g., charts, graphs) |

### Testing Tools

**Automated:**
- **Xcode Accessibility Inspector** (built-in):
  1. Run app in Xcode
  2. Open **Xcode > Open Developer Tool > Accessibility Inspector**
  3. Hover over UI elements to check contrast ratio
  4. ✅ Green check = WCAG AA compliant
  5. ⚠️ Yellow = WCAG AAA compliant only
  6. ❌ Red = fails WCAG AA

- **Color Contrast Analyzer** (free, desktop):
  - Download from [WebAIM](https://webaim.org/articles/contrast/)
  - Works with screen capture or color picker

**Manual:**
- Use macOS built-in loupe: Hold **Shift+Ctrl+D** with cursor over element
- Verify against [WCAG AA thresholds](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum)

### Current Status

All UI elements in the app use semantic colors (`Theme.swift`) that are tested for contrast:

```swift
// ✅ Tested: All semantic colors meet WCAG AA
Color.accentColor         // Primary action (≥4.5:1 on background)
Color.secondaryLabel      // Secondary text (≥4.5:1 on background)
Color.red                 // Error states (≥3:1 on white/light backgrounds)
Color.orange              // Warning states (≥3:1 on light backgrounds)
Color.gray                // Disabled states (≥3:1)
```

**When adding new colors:**
1. Test with **Accessibility Inspector** or **Color Contrast Analyzer**
2. Verify both on light AND dark backgrounds
3. Document contrast ratio in code comment:
   ```swift
   // Contrast ratio: 5.2:1 on light background, 4.8:1 on dark
   .foregroundColor(.accentColor)
   ```

## VoiceOver Testing (Screen Reader)

### What is VoiceOver?

VoiceOver is Apple's screen reader that reads UI elements aloud. Users navigate by swiping and tapping in specific patterns.

### Enable VoiceOver

**macOS:**
1. **System Preferences** > **Accessibility** > **VoiceOver**
2. Check **Enable VoiceOver** (shortcut: **Cmd+F5**)

**iOS:**
1. **Settings** > **Accessibility** > **VoiceOver**
2. Toggle **VoiceOver** ON

### Testing Procedure

1. **Enable VoiceOver** (above)
2. **Navigate the UI** by swiping right (next element) or left (previous element)
3. **Listen to announcements**:
   - ✅ Good: "Create Note button, double-tap to activate"
   - ❌ Bad: Silent or generic "Button 1"
4. **Verify all interactive elements** are reachable:
   - Text fields
   - Buttons
   - Sliders
   - Pickers
   - Segmented controls
   - Menu items
5. **Check image descriptions**:
   - ✅ Good: "Chart showing task completion over time"
   - ❌ Bad: "image.png" or no description

### SwiftUI Accessibility Modifiers

Use these modifiers to improve VoiceOver announcements:

```swift
// ✅ Good: Descriptive label and hint
Button(action: { createNote() }) {
    Label("New Note", systemImage: "square.and.pencil")
}
.accessibilityLabel("Create New Note")
.accessibilityHint("Opens the note editor to write a new note")

// ✅ Good: Combine multiple elements into single announcement
HStack {
    Image("priority")
    Text("High Priority")
}
.accessibilityElement(combining: .all)
.accessibilityLabel("Task Priority: High")

// ✅ Good: Remove redundant elements from VoiceOver
Image(systemName: "checkmark")
    .accessibilityHidden(true) // Checkmark already implied by button state
```

### Common Issues

| Issue | Fix |
|-------|-----|
| "Image.png" heard instead of description | Add `.accessibilityLabel()` to Image |
| Two announcements for button and icon | Combine with `.accessibilityElement(combining: .all)` |
| Read-only text is interactive | Add `.accessibilityAddTraits(.isStaticText)` |
| Custom control not announced | Add `.accessibilityElement()` + `.accessibilityLabel()` |

### Testing Scenarios

- [ ] **Note creation**: Create a note with VoiceOver on; verify all fields are read
- [ ] **Task list**: Navigate task list with VoiceOver; verify task title, priority, due date announced
- [ ] **Kanban board**: Navigate columns and cards; verify status, priority, labels announced
- [ ] **Search**: Perform search with VoiceOver; verify results announced with snippet
- [ ] **Menu navigation**: Tap menu buttons and confirm menu items are readable

## Voice Control

### What is Voice Control?

Voice Control lets users operate the app entirely by voice (hands-free access). Available on iOS 13+ and macOS 10.15+.

### Enable Voice Control

**macOS:**
1. **System Preferences** > **Accessibility** > **Voice Control**
2. Check **Enable Voice Control** (shortcut: **Fn Fn** twice)
3. Press Fn and say "Show numbers" to see clickable elements

**iOS:**
1. **Settings** > **Accessibility** > **Voice Control**
2. Toggle **Voice Control** ON
3. Say "Show numbers" to see clickable elements

### Testing Procedure

1. **Enable Voice Control** (above)
2. **Say "Show numbers"** — Each interactive element gets a number
3. **Say the number** to activate that element
4. **Test these workflows**:
   - Create a note ("Say 'New Note', then dictate text")
   - Complete a task ("Say task number to select, then say 'Done'")
   - Filter tasks ("Say 'Filter', then say 'Today'")
   - Open settings ("Say 'Settings'")

### Common Issues

| Issue | Fix |
|-------|-----|
| Button is not numbered (can't activate by voice) | Add `.accessibility Label()` to button |
| Menu items not numbered | Ensure menu items have labels |
| Custom gesture not voice-controllable | Map to `.onTapGesture` (supports voice) |

### Voice Control Checklist

- [ ] All buttons have clear, unique labels (no "Button 1", "Button 2")
- [ ] Text fields can be activated and typed into by voice
- [ ] Pickers and dropdowns can be opened and options selected
- [ ] Gestures (swipe, drag) have voice alternatives (buttons, menus)
- [ ] All numbered elements are useful (remove `.accessibilityHidden()` from elements you want voice-accessible)

## Dynamic Type (Font Scaling)

### What is Dynamic Type?

Dynamic Type allows users to adjust system font size (for readability). Text that respects Dynamic Type scales automatically.

### Test Font Scaling

**macOS:**
1. **System Preferences** > **Accessibility** > **Display**
2. Adjust **Larger Accessibility Sizes** (or Standard Sizes)

**iOS:**
1. **Settings** > **Accessibility** > **Display & Text Size**
2. Drag **Larger Accessibility Sizes** to maximum
3. Return to app; all text should scale up

### Checking Your Code

In SwiftUI, use **semantic font sizes** (automatically scale):

```swift
// ✅ Good: Scales with system Dynamic Type
Text("My Note")
    .font(.headline)           // Scales automatically
    .lineLimit(2)              // Prevent text cutoff

// ❌ Avoid: Fixed size, doesn't scale
Text("My Note")
    .font(.system(size: 16))   // Doesn't scale; breaks accessibility

// ✅ Good: Custom font with explicit Dynamic Type support
Text("My Note")
    .font(.system(size: 16, weight: .semibold, design: .default))
    .dynamicTypeSize(.medium ... .xxxLarge)  // Explicit bounds
```

### Layout Considerations

When testing at large font sizes:

- [ ] Text doesn't overflow or get cut off
- [ ] Buttons remain ≥44pt tall (touch target)
- [ ] Multi-line text wraps correctly
- [ ] Labels and values don't overlap
- [ ] Modal dialogs fit on screen

**Common issue**: Text overflows button or card
**Fix**: Use `.lineLimit(2)` or `.truncationMode(.tail)`, or increase container height at larger sizes:

```swift
VStack(spacing: 8) {
    Text("Task Title")
        .font(.headline)
        .lineLimit(2)

    Text("Task Details")
        .font(.body)
        .lineLimit(3)
}
.frame(height: sizeClass == .accessibility ? 120 : 100)  // Taller at large type
```

## Touch Targets (Hit Area)

### Requirement

All interactive elements must be **≥44x44 points** (iOS) or **≥48x48 points** (macOS recommended) for finger tapping.

### Testing

**Visual Inspection:**
1. Run app on device
2. Try to tap each button/icon
3. ✅ Easy to tap without missing = meets requirement
4. ❌ Hard to tap, miss frequently = too small

**Measurement (Xcode):**
1. Open **Accessibility Inspector** in Xcode
2. Hover over element
3. Check **Size** field — should show ≥44x44

### Fixing Small Touch Targets

```swift
// ❌ Too small: 24x24
Button(action: deleteNote) {
    Image(systemName: "trash")
        .frame(width: 24, height: 24)
}

// ✅ Correct: 48x48 hit area with smaller visual size
Button(action: deleteNote) {
    Image(systemName: "trash")
        .frame(width: 24, height: 24)
}
.frame(minWidth: 48, minHeight: 48)  // Invisible hit area
```

## High Contrast Mode

### What is High Contrast?

High Contrast Mode increases contrast between UI elements (useful for users with low vision).

### Test High Contrast

**macOS:**
1. **System Preferences** > **Accessibility** > **Display**
2. Check **Increase contrast**
3. Test app — colors should still be clearly distinguishable

**iOS:**
1. **Settings** > **Accessibility** > **Display & Text Size**
2. Toggle **Increase Contrast** ON
3. Return to app

### Common Issues

- [ ] Links are not underlined or bold (look like regular text in high contrast)
- [ ] Disabled buttons are indistinguishable from enabled
- [ ] Icons without text labels are unclear
- [ ] Colors are the only way to convey information

**Fixes:**
- Add text labels to icons
- Underline links: `.underline()`
- Use patterns/textures in addition to color (e.g., stripes for warnings)
- Bold or darken disabled state

## Zoom Testing

### Test at 200% Zoom

**macOS:**
1. **System Preferences** > **Accessibility** > **Zoom**
2. Check **Use keyboard shortcuts to zoom**
3. Press **Cmd+Plus** to zoom to 200%

**iOS:**
1. **Settings** > **Accessibility** > **Zoom**
2. Toggle **Zoom** ON
3. Double-tap with two fingers to zoom (or pinch to adjust)

### Check for Issues

- [ ] UI doesn't overlap or break layout
- [ ] All text remains readable
- [ ] Buttons are still tappable
- [ ] Scrolling still works
- [ ] Modals fit on screen

## Testing Automation

### ViewInspector + Accessibility

The test suite includes accessibility checks via `ViewInspector`:

```swift
// Example: Verify button has accessibility label
func testCreateNoteButtonIsAccessible() throws {
    let button = try view.find(button: "Create Note")
    let label = try button.accessibilityLabel()
    XCTAssertEqual(label, "Create New Note")
}
```

See `Tests/NotesUITests/AccessibilityTests.swift` for comprehensive examples.

## Common a11y Mistakes

| Mistake | Impact | Fix |
|---------|--------|-----|
| **No color description in VoiceOver** | Color-blind users can't understand state | Add `.accessibilityLabel()` |
| **Text too small** | Users can't read | Use semantic font sizes or minimum 12pt |
| **Touch target <44pt** | Hard to tap (especially on iPhone) | Add `.frame(minWidth: 48, minHeight: 48)` |
| **Image with no alt text** | VoiceOver silent | Add `.accessibilityLabel()` |
| **Links same color as text** | Users can't see they're clickable | Underline or bold links |
| **Video without captions** | Deaf users excluded | Add video captions/transcripts |
| **Custom gesture only** | Voice Control users stuck | Add button alternative |

## Resources

- **[Apple Accessibility Documentation](https://developer.apple.com/accessibility/swiftui/)**
- **[WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)**
- **[WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/)**
- **[Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/accessibility)**

## Pre-Release Accessibility Audit

Before public release, all UI screens must pass:

- [ ] WCAG AA color contrast (Accessibility Inspector)
- [ ] VoiceOver navigation (all elements reachable and announced)
- [ ] Voice Control compatibility (all actions voice-activatable)
- [ ] Dynamic Type at large sizes (no overflow or layout break)
- [ ] Touch targets ≥44pt (tested on device)
- [ ] High Contrast mode (no color-only states)
- [ ] Zoom at 200% (layout intact, readable)

Audit results should be documented in the release notes.

---

**Last Updated**: 2026-03-03
**Status**: Ready for integration into PR review process
