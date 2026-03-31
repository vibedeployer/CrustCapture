# CrustCapture

A professional macOS screen recording app with automatic zoom-on-click, cursor tracking, and beautiful export effects.

Built by [MoonCrust Games](https://github.com/vibedeployer).

## Features

**Recording**
- Screen or window capture via ScreenCaptureKit
- 30/60 fps recording with system audio
- Cursor position and click tracking
- Auto-hide window during recording
- Crop title bar option for clean browser recordings
- 3-2-1 countdown with sound
- Menu bar icon for quick start/stop
- Keyboard shortcut (Cmd+Shift+R)

**Editor**
- Live preview with all effects applied
- Timeline with thumbnail strip and trim handles
- Playback with spacebar toggle
- Undo/redo (Cmd+Z / Cmd+Shift+Z)

**Effects**
- 15 background presets (gradients + solids) + custom color picker
- Rounded corners with native macOS window corner support
- Drop shadow with configurable radius and opacity
- Cursor highlight with click pulse animation
- Auto-zoom on click — stays zoomed during rapid clicking, smooth pan between click clusters

**Export**
- MP4 export with H.264 or HEVC codec
- GIF export
- Resolution options: 1080p, 1440p, Original
- Quality presets: Optimized (8 Mbps), High (20 Mbps), Maximum (50 Mbps)
- Progress overlay with cancel support

## Requirements

- macOS 14.0+
- Screen Recording permission

## Installation

### From DMG
1. Download `CrustCapture-1.0.dmg` from [Releases](../../releases)
2. Open the DMG and drag CrustCapture to Applications
3. Right-click the app > Open (required first time since unsigned)
4. Grant Screen Recording permission when prompted

### Build from Source
```bash
git clone https://github.com/vibedeployer/CrustCapture.git
cd CrustCapture
xcodebuild -scheme CrustCapture -configuration Release build
```

## Tech Stack

- SwiftUI
- ScreenCaptureKit
- AVFoundation
- Core Image + Metal (GPU-accelerated compositor)

## License

Copyright 2026 MoonCrust Games. All rights reserved.
