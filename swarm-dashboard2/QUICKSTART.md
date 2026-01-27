# Swarm Dashboard 2 - Quick Start Guide

**Version**: 2.0 BETA (Mouse Support)
**Last Updated**: January 27, 2026

---

## 30-Second Start

```bash
cd /home/mojo/projects/ralphussy
bun swarm-dashboard2/src/index.ts
```

Press `?` for help inside the TUI.

---

## Essential Keybindings

| Key | What It Does |
|-----|-------------|
| `?` | Show help (all keybindings) |
| `o` | Options menu (with mouse support!) |
| `d` | DevPlan interview instructions |
| `s` | Start new swarm |
| `e` | Emergency stop |
| `q` | Quit |
| `Tab` | Switch focused pane |
| `↑`/`↓` | Scroll |
| `Escape` | Close modals |

---

## Mouse Support (NEW!)

**In Options Menu** (press `o`):
- ✅ Click tabs to switch sections
- ✅ Click fields to change values
- ✅ Click outside to close

**To verify it works**:
1. Press `o` for options
2. Look at **Ralph Live** pane (bottom right)
3. Should see: `[MOUSE] Mouse handler initialized`
4. Try clicking - each click is logged

---

## Common Tasks

### Start a Swarm
```
Press 's' → Fill in details → Press Enter
```

### Change Models
```
Press 'o' → Navigate to Swarm/Ralph section → Select provider/model
```

Or use mouse:
```
Press 'o' → Click "Swarm" tab → Click "Provider" to cycle
```

### Generate DevPlan
```
Press 'd' → Read instructions → Close TUI → Run command shown
```

### View Task Details
```
Tab to Tasks pane → Up/Down to select → Enter to open details
```

### Filter Ralph Live by Task
```
Press 't' → Select task → See only that task's logs
```

---

## Configuration Location

All settings saved to:
```
~/.ralph/config.json
```

---

## Troubleshooting

### Terminal Broken After Exit
```bash
reset
```

### Mouse Not Working
1. Check Ralph Live for `[MOUSE] Mouse handler initialized`
2. If missing, try different terminal (iTerm2, Alacritty, Kitty)
3. Some terminals don't support mouse events

### Can't See Recent Logs
```
Press 'r' to refresh manually
Or: Press 'o' → Settings → Toggle "Auto Refresh" ON
```

---

## Help & Documentation

- Press `?` inside TUI for full keybinding list
- Read `README.md` for complete documentation
- Check `HANDOFF.md` for developer details

---

**Pro Tip**: Enable debug mode to see what's happening behind the scenes:
```
Press 'o' → Click/navigate to Settings → Toggle "Debug Mode" ON
```

All events and actions will be logged to Ralph Live pane!
