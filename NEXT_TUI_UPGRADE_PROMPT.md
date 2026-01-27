# Task: Major TUI Upgrades - Mouse Support & Visual Enhancements

## Context

You are a senior developer working on the `ralphussy` project. The main TUI dashboard lives at `swarm-dashboard2/src/index.ts` and is built with **OpenTUI** (`@opentui/core`). Your task is to make major upgrades to the TUI, adding mouse support, visual improvements, and better user experience.

## Current State

The dashboard (`swarm-dashboard2/src/index.ts`) is a Ralph Live Dashboard that:
- Monitors swarm agent runs with real-time status
- Has an Options modal with 5 tabbed sections (MODE, SWARM, RALPH, DEVPLAN, SETTINGS)
- Supports keyboard navigation only (no mouse)
- Uses basic text rendering without advanced visual features
- Run it with: `./run-swarm-dashboard2.sh`

## Your Objectives

### 1. Add Mouse Support

OpenTUI supports mouse events. Implement:

- **Clickable elements**: Buttons, tabs, list items should respond to clicks
- **Hover states**: Visual feedback when hovering over interactive elements
- **Scroll support**: Mouse wheel scrolling in log panels and lists
- **Click-to-focus**: Click on inputs/selects to focus them

**Implementation hints from OpenTUI:**
```typescript
// Mouse events are available through the renderer's input system
renderer.keyInput.on("mouse", (event) => {
  // event.x, event.y - coordinates
  // event.button - which button
  // event.action - press, release, move, scroll
})
```

### 2. Visual Upgrades Using OpenTUI Features

Leverage these OpenTUI renderables for visual improvements:

#### ASCII Art Title
```typescript
import { ASCIIFontRenderable, RGBA } from "@opentui/core"

const title = new ASCIIFontRenderable(renderer, {
  id: "title",
  text: "RALPH",
  font: "tiny",  // Available: tiny, small, standard, etc.
  color: RGBA.fromHex("#00FF00"),
  position: "absolute",
  left: 2,
  top: 1,
})
```

#### Styled Text with Attributes
```typescript
import { t, bold, underline, fg, bg } from "@opentui/core"

// Template literal styling
const styledContent = t`${bold("Status:")} ${fg("#00FF00")("Running")} | ${underline("Workers:")} 4`
```

#### Better Boxes with Borders
```typescript
import { BoxRenderable } from "@opentui/core"

const panel = new BoxRenderable(renderer, {
  borderStyle: "double",  // Options: single, double, rounded, heavy, etc.
  borderColor: "#4488FF",
  backgroundColor: "#1a1a2e",
  title: "Agent Status",
  titleAlignment: "center",
  // ... layout props
})
```

#### TabSelect for Modal Navigation
```typescript
import { TabSelectRenderable, TabSelectRenderableEvents } from "@opentui/core"

const tabs = new TabSelectRenderable(renderer, {
  options: [
    { name: "MODE", description: "Select operation mode" },
    { name: "SWARM", description: "Swarm configuration" },
    { name: "RALPH", description: "Ralph settings" },
    { name: "DEVPLAN", description: "DevPlan models" },
    { name: "SETTINGS", description: "General settings" },
  ],
  tabWidth: 12,
})

tabs.on(TabSelectRenderableEvents.ITEM_SELECTED, (index, option) => {
  // Handle tab selection
})
```

#### Select for Dropdown Menus
```typescript
import { SelectRenderable, SelectRenderableEvents } from "@opentui/core"

const modelSelect = new SelectRenderable(renderer, {
  options: providers.map(p => ({ name: p, description: `${modelCounts[p]} models` })),
  // ...
})

modelSelect.on(SelectRenderableEvents.ITEM_SELECTED, (index, option) => {
  // Handle selection
})
```

#### Input Fields
```typescript
import { InputRenderable, InputRenderableEvents } from "@opentui/core"

const input = new InputRenderable(renderer, {
  placeholder: "Enter project name...",
  focusedBackgroundColor: "#2a2a4e",
  // ...
})

input.on(InputRenderableEvents.CHANGE, (value) => {
  // Handle input change
})
```

### 3. UI/UX Improvements

#### Color Scheme
Use a consistent, modern color palette:
```typescript
const COLORS = {
  background: "#0d1117",
  surface: "#161b22",
  surfaceHover: "#21262d",
  border: "#30363d",
  borderFocus: "#58a6ff",
  text: "#c9d1d9",
  textMuted: "#8b949e",
  accent: "#58a6ff",
  success: "#3fb950",
  warning: "#d29922",
  error: "#f85149",
}
```

#### Layout Improvements
- Use Yoga flexbox layout for responsive design
- Add proper spacing and padding
- Group related information visually
- Use visual hierarchy (size, color, position)

#### Status Indicators
- Use colored dots/icons for status (green=running, yellow=pending, red=error)
- Add progress bars for long operations
- Show timestamps for recent activity

#### Help System
- Add a help modal (press `?`) showing all keybindings
- Show context-sensitive hints at the bottom
- Add tooltips on hover (where applicable)

### 4. Specific Features to Add

1. **Clickable run list** - Click to select a run instead of just keyboard
2. **Hover highlights** - Visual feedback on hoverable items
3. **Modal close on click outside** - Standard UX pattern
4. **Scroll indicators** - Show when content is scrollable
5. **Progress animations** - Animated spinners/progress for loading states
6. **Toast notifications** - Brief popup messages for actions
7. **Keyboard shortcut legend** - Always visible at bottom
8. **Responsive layout** - Adapt to different terminal sizes

## OpenTUI Reference

### Key APIs

```typescript
import {
  createCliRenderer,
  TextRenderable,
  BoxRenderable,
  GroupRenderable,
  InputRenderable,
  SelectRenderable,
  TabSelectRenderable,
  ASCIIFontRenderable,
  FrameBufferRenderable,
  RGBA,
  t, bold, underline, fg, bg,
  TextAttributes,
} from "@opentui/core"

// Create renderer
const renderer = await createCliRenderer({
  consoleOptions: {
    position: ConsolePosition.BOTTOM,
    sizePercent: 30,
  },
})

// Keyboard input
renderer.keyInput.on("keypress", (key) => {
  // key.name, key.ctrl, key.shift, key.meta
})

// Colors
const color = RGBA.fromHex("#FF0000")
const color2 = RGBA.fromInts(255, 0, 0, 255)

// Layout (Yoga flexbox)
const container = new GroupRenderable(renderer, {
  flexDirection: "row",
  justifyContent: "space-between",
  alignItems: "center",
  width: "100%",
  height: 10,
})
```

### Console/Debug
```typescript
// Built-in console overlay - toggle with backtick (`) by default
renderer.console.toggle()

// Console captures console.log, console.error, etc.
console.log("Debug info")  // Shows in overlay
```

## File Locations

- **Main TUI**: `swarm-dashboard2/src/index.ts`
- **Database helper**: `swarm-dashboard/src/database-bun.ts`
- **Run script**: `./run-swarm-dashboard2.sh`
- **Config file**: `~/.ralph/config.json`

## Testing

1. Run the dashboard: `./run-swarm-dashboard2.sh`
2. Test mouse clicks on various elements
3. Test hover states
4. Test scroll behavior
5. Test keyboard shortcuts still work
6. Test in different terminal sizes
7. Verify no regressions in existing functionality

## Success Criteria

- [ ] Mouse clicks work on interactive elements (buttons, tabs, list items)
- [ ] Hover states provide visual feedback
- [ ] Mouse wheel scrolling works in scrollable areas
- [ ] ASCII art title looks good
- [ ] Consistent color scheme throughout
- [ ] TabSelect used for modal tab navigation
- [ ] Select/Input renderables used where appropriate
- [ ] Help modal accessible via `?`
- [ ] Keyboard shortcuts still work as before
- [ ] No performance regressions
- [ ] Works in standard terminal sizes (80x24 and larger)

## Notes

- OpenTUI is in active development - check latest docs if something doesn't work
- The dashboard currently uses React reconciler patterns but can use raw renderables
- Keep backwards compatibility with existing keyboard-only users
- Test on both light and dark terminal themes
- Console captures `console.log` - use `renderer.console.toggle()` or backtick to view

Good luck! Make that TUI beautiful and user-friendly.
