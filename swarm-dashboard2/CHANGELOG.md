# Changelog

All notable changes to Swarm Dashboard 2 will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.0.0-beta] - 2026-01-27

Major update with mouse support and improved DevPlan integration.

### Added
- **Mouse Support (BETA)** - Click to interact with options menu
  - Click tabs to switch sections (Mode, Swarm, Ralph, Devplan, Settings)
  - Click fields to focus and cycle through values
  - Click outside modal to close
  - Comprehensive logging for debugging mouse events
  - Fallback methods to access blessed screen object
- **DevPlan Interactive Interview Instructions** - Press 'D' for guidance
  - Auto-detects project directory from `~/projects/current`
  - Displays exact command to run the interview
  - Shows in modal overlay with clear instructions
  - No longer crashes the TUI
- **Debug Logging System**
  - `[MOUSE]` prefix for all mouse-related events
  - `[MOUSE ERR]` for mouse errors
  - Mouse handler initialization confirmation
  - Coordinate logging when options menu is open
- **Help Keybinding** - Press '?' to show full help modal
- **Documentation**
  - `HANDOFF.md` - Comprehensive development handoff
  - `QUICKSTART.md` - Quick reference guide
  - `CHANGELOG.md` - This file

### Changed
- **'D' Key Behavior** - Now shows instructions instead of launching interview
  - Previous: Attempted to exit TUI and spawn devussy CLI (caused crashes)
  - Current: Shows modal with instructions and command
  - Reason: More reliable, better UX, no terminal state corruption
- **Options Menu** - Enhanced with mouse interaction
  - Keyboard navigation still works as before
  - Mouse support added as additional input method
  - Both methods can be used interchangeably
- **README.md** - Updated with mouse support documentation
  - Added mouse interaction guide
  - Updated keyboard controls table
  - Enhanced troubleshooting section
  - Added recent updates section

### Fixed
- **TUI Crash on 'D' Key** - No longer crashes when opening DevPlan
  - Root cause: `spawnSync` with `stdio: 'inherit'` corrupted terminal state
  - Solution: Display instructions modal instead of spawning process
- **Options Menu Not Clickable** - Mouse events now handled
  - Root cause: No mouse event listeners registered
  - Solution: Added React.useEffect with screen.on('mouse', handler)
- **Terminal State Corruption** - Clean exit and restoration
  - Added proper cleanup in mouse handler effect return
  - Instructions guide users to exit cleanly before running commands

### Technical Details

**Files Modified**:
- `swarm-dashboard2/src/index.ts` (Lines 1246-1649)
  - DevPlan instructions modal (Lines 1246-1303)
  - Mouse event handling (Lines 1329-1649)

**Dependencies**:
- @opentui/react: 0.1.74 (unchanged)
- @opentui/core: 0.1.74 (unchanged)

**Configuration**:
- No breaking changes to `~/.ralph/config.json` format
- All existing configs remain compatible

---

## [1.0.0] - 2026-01-26

Initial release of Swarm Dashboard 2 with modern React + OpenTUI architecture.

### Added
- React-based TUI using @opentui/react
- Options menu with 5 configurable sections
- DevPlan generation wizard (form-based)
- Full scrolling support (per-pane and global)
- Dynamic sizing based on content
- Detail views for tasks and workers
- Live updates with configurable polling
- Keyboard navigation
- Focus indicators
- Config persistence to `~/.ralph/config.json`
- Support for multiple LLM providers
- Cost tracking and display
- Ralph Live log filtering by task
- Historical run selection

### Features
- **Options Menu** (Press 'O')
  - MODE: Select operation mode (ralph/devplan/swarm)
  - SWARM: Configure swarm provider, model, agent count
  - RALPH: Configure ralph provider and model
  - DEVPLAN: Granular model selection per pipeline stage
  - SETTINGS: General configuration (timeouts, polling, debug mode)
- **DevPlan Generation** (Press 'D')
  - Multi-step interview form
  - Auto-detection of project name
  - Pipeline progress tracking
  - Output to `~/.ralph/devplans/`
- **Navigation**
  - Tab: Cycle through panes
  - Up/Down: Scroll focused pane
  - PageUp/PageDown: Fast scroll
  - Shift+Up/Down: Global dashboard scroll
  - Enter/Space: Open detail view
  - Escape: Close overlays
- **Swarm Control**
  - Start new runs
  - Emergency stop
  - Attach to running swarms
  - View historical runs
  - Manual refresh

### Technical
- Runtime: Bun
- UI Framework: React + @opentui/react
- Database: SQLite (via swarm-dashboard helper)
- Config: JSON file at `~/.ralph/config.json`
- Launcher: `run-swarm-dashboard2.sh`

---

## [0.1.0] - Pre-release

Development versions before official release.

---

## Versioning Strategy

- **Major (X.0.0)**: Breaking changes, major feature overhauls
- **Minor (1.X.0)**: New features, non-breaking changes
- **Patch (1.0.X)**: Bug fixes, minor improvements
- **Beta (-beta)**: Features in testing, may have issues

---

## Upgrade Notes

### From 1.0.0 to 2.0.0-beta

**No action required** - Fully backward compatible!

The only changes are additions:
- Mouse support in options menu (optional feature)
- DevPlan instructions modal (replaces wizard)
- Debug logging (optional, enable in settings)

Your existing:
- Config file works as-is
- Keyboard shortcuts unchanged
- Database queries unchanged
- Launcher scripts unchanged

**If you want to use mouse support**:
1. Launch TUI as normal
2. Press 'O' for options menu
3. Try clicking! (check Ralph Live for `[MOUSE]` messages)

**If mouse doesn't work**:
- No problem! All features still work with keyboard
- Mouse is an **optional enhancement**, not required

---

## Known Issues

### 2.0.0-beta

- **Mouse coordinate mapping** may need adjustment for some screen sizes
- **Mouse events** not supported in all terminal emulators
- **Screen object access** uses undocumented API (may break in future @opentui updates)
- **DevPlan interview** requires manual command execution (not integrated into TUI)

See `HANDOFF.md` for detailed information on these issues and potential solutions.

---

## Future Roadmap

### Next Release (2.1.0)
- [ ] Mouse support for task/worker selection
- [ ] Click-to-focus for panes
- [ ] Hover tooltips
- [ ] Scroll wheel for pane scrolling

### Future (3.0.0)
- [ ] Integrated DevPlan interview (if terminal control issues resolved)
- [ ] Drag-and-drop task reordering
- [ ] Context menus (right-click)
- [ ] Visual theme customization
- [ ] Plugin system for custom panels

---

## Contributing

Before contributing:
1. Read `README.md` for usage guide
2. Read `HANDOFF.md` for technical details
3. Check this CHANGELOG for current state
4. Test your changes in multiple terminals

---

## Support

- **Issues**: Report at GitHub Issues
- **Questions**: Check README.md and HANDOFF.md first
- **Feature Requests**: Open an issue with `[Feature]` prefix

---

**Last Updated**: January 27, 2026
**Maintained By**: Ralph Development Team
