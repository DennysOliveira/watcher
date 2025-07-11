# Watcher: Economy
> An addon to track your economy activities in ArcheAge Classic with detailed session management.
> Comprehensive gold and labor tracking with historical analysis.
> Created by Winterflame for ArcheAge Classic.

## Overview
Watcher is a comprehensive economy tracking addon that monitors your gold and labor changes in real-time, organizing them into sessions for detailed analysis and historical review.

## How to use
- **Open Watcher**: Click the "Open Watcher" button in your bag interface
- **View Current Session**: See your current session's gold start/end values and recent activity
- **Session History**: Click "Session History" to view all your past sessions
- **New Session**: Click "New Session" to start a fresh tracking session
- **Navigate History**: Use pagination controls to browse through your activity history

## Features

### Real-time Tracking
- **Automatic monitoring**: Tracks gold and labor changes as they happen
- **Event association**: Intelligently groups related gold and labor events
- **Session management**: Organizes activities into discrete sessions
- **Live updates**: UI updates immediately when changes occur

### Session Management
- **Automatic session creation**: New sessions start when you begin playing
- **Session persistence**: All data is saved between game sessions
- **Session ending**: Automatically closes sessions when you log out
- **Manual control**: Start new sessions anytime with the "New Session" button

### Detailed History
- **Comprehensive logging**: Records every gold and labor change with timestamps
- **Pagination**: Browse through large amounts of historical data
- **Color coding**: Green for positive gold changes, red for negative
- **Time formatting**: Shows relative times (Today, Yesterday, etc.)

### Session History UI
- **Overview statistics**: Total labor used and gold earned across all sessions
- **Session summaries**: Quick view of each session's performance
- **Current session highlighting**: Clearly marks your active session
- **Scrollable interface**: Easy navigation through session history

### Data Analysis
- **Gold tracking**: Start money, end money, and net changes
- **Labor tracking**: Used labor and earned labor separately
- **Aggregate calculations**: Automatic computation of session totals
- **Stale session cleanup**: Removes empty or zero-activity sessions

## Technical Details
- **Event monitoring**: Listens to LABORPOWER_CHANGED and PLAYER_MONEY events
- **File-based storage**: Sessions saved as individual files with index
- **Memory efficient**: Only loads current session data into memory
- **Error handling**: Graceful handling of missing or corrupted data

## Tips
- Sessions automatically start when you first use labor or money
- Use "New Session" to separate different activities (crafting, trading, etc.)
- Session History shows the most recent sessions first
- The addon automatically cleans up empty sessions on load
- All timestamps are converted to your local time zone

## Data Storage
- Session files: `watcher/data/sessions/[CharacterName]_[SessionID].txt`
- Session index: `watcher/data/session_index.txt`
- Each session contains detailed stamps of every gold/labor change

Perfect for players who want to track their economy progress, analyze their earning patterns, and maintain detailed records of their ArcheAge Classic activities.
