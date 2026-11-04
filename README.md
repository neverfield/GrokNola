# GrokNola

Grok Notes is a Granola-style meeting notepad for macOS that runs entirely on the xAI API.
No bot joins the call. It listens to your microphone and your Mac's audio,
transcribes live with `grok-voice-transcribe-2.0`, and writes notes with `grok-4.7`.

## Build and run

```bash
./scripts/build-app.sh
open "build/Grok Notes.app"
```

Requires macOS 14+ and Xcode command-line tools. Open Settings (Command-comma),
paste your xAI API key (stored in the Keychain), and grant the permissions.
Grant Screen & System Audio Recording, then relaunch the app.

Permissions are tied to the code signature. Run `./scripts/create-signing-cert.sh`
once to create a local signing certificate. The build script then uses it, so
rebuilds keep their permissions. Set `CODESIGN_IDENTITY` to use another certificate.

## Use

1. When a call starts, click **Start notes** (window, menu bar, or Shift-Command-R).
   The menu bar icon changes when it detects a meeting in Zoom, Teams, Meet, Slack, Webex, or FaceTime.
2. Type rough notes while you talk. The transcript fills in live.
3. Click **Stop**. Grok re-transcribes the full recording, names the speakers,
   and writes enhanced notes built around your rough notes.
4. Use **Ask Grok** for questions or follow-up drafts. Click any speaker name to correct it.

## How speakers get names

| Signal | Needs | Result |
| --- | --- | --- |
| Microphone vs. system audio on separate streams | Microphone + Screen & System Audio Recording | You vs. everyone else |
| Diarization of system audio | Same | Remote voices split into separate speakers |
| The meeting app's "who is talking" indicator, read through Accessibility and matched to speech timing | Accessibility | Real names (`active speaker`) |
| Calendar invitees plus Grok reading the transcript for introductions and name use | Calendar (optional) | Real names (`inferred`) with a confidence bar |
| Your corrections | None | Saved, and reused as hints in later meetings |

A speaker without strong evidence stays **Them**, so you fall back to Me / Them
when permissions are missing or the app is not supported. Without system audio,
the microphone alone is diarized and the main voice is labeled as you.

The active-speaker patterns in `Sources/GrokNotes/Speakers/ActiveSpeakerMonitor.swift`
are heuristics. Meeting apps change their labels, so add a pattern there if names stop appearing.

## Ask across notes

**Ask across notes** at the top of the sidebar (Command-K) is one chat over every meeting.
Grok ranks meetings by keywords, names, and recency, picks the most relevant ones from a
compact index, then answers from their notes and transcripts. Each answer links to its
source meetings; click a link to open the meeting. The search field above the meeting list
filters by title, notes, people, and transcript text. The chat history is saved in
`~/Library/Application Support/GrokNotes/library-chat.json`.

## Cost

**Meeting > Usage & Cost** (Shift-Command-U, or the menu bar) shows xAI spend for today,
the last 7 days, this month, or all time, broken down by feature and by meeting. Each meeting
header also shows its own cost. Grok requests use the exact `cost_in_usd_ticks` that xAI
returns. Transcription is estimated from recorded audio at list price ($0.20 per hour
streaming, $0.10 per hour for the full-recording pass). The log is
`~/Library/Application Support/GrokNotes/usage.jsonl`.

## Data

Everything lives in `~/Library/Application Support/GrokNotes/Meetings/<id>/`
(`meeting.json`, `notes.md`, and the audio if you choose to keep it).
Audio and text leave the Mac only to reach `api.x.ai`.

### Google Drive (optional)

With **Google Drive for desktop** installed and signed in, you can mirror exports into synced **My Drive**:

1. Open Settings (Command-comma) → **Google Drive**.
2. Turn on **Copy notes to Google Drive when saved**.
3. Optionally set a **Subfolder under My Drive** (for example `Grok Notes`). Leave it blank to write at the top level of My Drive.

On each save, Grok Notes copies `notes.md` and `meeting.json` into:

`~/Library/CloudStorage/GoogleDrive-<account>/My Drive/<subfolder>/<yyyy-MM-dd Meeting title>/`

Folder names use the meeting start date and a sanitized title. If Drive is not mounted, the app keeps saving locally and logs an export failure; it does not block saves or show an error banner.
