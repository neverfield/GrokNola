# GrokNola

GrokNola is a Granola-style meeting notepad for macOS that runs entirely on the xAI API.
No bot joins the call. It listens to your microphone and your Mac's audio,
transcribes live with `grok-voice-transcribe-2.0`, and writes notes with `grok-4.7`.

## Build and run

```bash
./scripts/build-app.sh
open "build/GrokNola.app"
```

Requires macOS 14+ and Xcode command-line tools. Open Settings (Command-comma),
paste your xAI API key (stored in the Keychain), and grant the permissions.
Grant Screen & System Audio Recording, then relaunch the app.

Permissions are tied to the code signature. Run `./scripts/create-signing-cert.sh`
once to create a local signing certificate. The build script then uses it, so
rebuilds keep their permissions. Set `CODESIGN_IDENTITY` to use another certificate.

The app icon is `Resources/AppIcon.icns`, built from `Resources/AppIcon-master.png` (shaped by `scripts/shape-icon.swift`; other concepts in `Resources/icon-options/`).

## Use

1. When a call starts, click **Start notes** (window, menu bar, or Shift-Command-R).
   The menu bar icon changes when it detects a meeting in Zoom, Teams, Meet, Slack, Webex, or FaceTime.
2. Type rough notes while you talk. The transcript fills in live, and a **Live** strip under the
   notepad shows the latest lines. Level meters in the bottom bar show that the mic and call audio
   are arriving; a meter turns orange when a side has been silent for 20 seconds.
3. Click **Stop & Write Notes**. Grok re-transcribes the full recording, names the speakers,
   writes enhanced notes built around your rough notes, and tags the meeting. The Notes tab shows
   each step; a failed step has **Retry**. A "Notes ready" notification opens the meeting.
4. Switch between **Notes**, **Transcript**, and **Ask** in the toolbar (Command-1/2/3). Use the
   meeting's **Ask** tab for questions or follow-up drafts. Click any speaker name to correct it.
5. Enhanced notes select and copy across lines. Click **Edit** to fix a name or line in the Markdown,
   and click a checkbox to mark an action item done. Timestamps show as pills: **▶ 5:17** plays the
   clip (Option-click opens the transcript), **5:17** opens the transcript when no audio was kept.
6. The toolbar **…** menu has Regenerate Notes (Option-Command-R), Edit Notes, Copy Markdown
   (Shift-Command-C), Copy Transcript, Find in Transcript, Show in Finder, and Delete Meeting.
   **Share** sends the Markdown to another app. **Copy Transcript** writes `[mm:ss] Name: text` lines
   with `## Chapter (mm:ss–mm:ss)` headings. Each chapter title has its own copy icon, and
   right-clicking a block copies that block.
7. In the **Transcript** tab, Command-F finds text: Return and Shift-Return step through matches.
8. Deleting a meeting moves it to `~/Library/Application Support/GrokNotes/Trash/`. Click **Undo**
   in the bar that appears, or press Command-Z. The trash is emptied of meetings older than 30 days at launch.
9. With kept audio, the speaker icon in the player opens separate **My voice** and **Others**
   sliders (−12 to +12 dB around the balanced level), mute buttons, and **Balance voices**.

## How speakers get names

| Signal | Needs | Result |
| --- | --- | --- |
| Microphone vs. system audio on separate streams | Microphone + Screen & System Audio Recording | You vs. everyone else |
| Diarization of system audio | Same | Remote voices split into separate speakers |
| The meeting app's "who is talking" indicator, read through Accessibility and matched to speech timing | Accessibility | Real names (`active speaker`) |
| Calendar invitees plus Grok reading the transcript for introductions and name use | A calendar source (optional, see [Calendar](#calendar)) | Real names (`inferred`) with a confidence bar |
| Your corrections | None | Saved, and reused as hints in later meetings |

A speaker without strong evidence stays **Them**, so you fall back to Me / Them
when permissions are missing or the app is not supported. Without system audio,
the microphone alone is diarized and the main voice is labeled as you.

The active-speaker patterns in `Sources/GrokNotes/Speakers/ActiveSpeakerMonitor.swift`
are heuristics. Meeting apps change their labels, so add a pattern there if names stop appearing.

## Calendar

GrokNola uses your calendar to title a meeting, list its invitees, and show
**Up next** on Home (today's remaining events with **Join** and **Start notes**).
Pick the source in **Settings > Calendar & Drive**:

| Source | Reads |
| --- | --- |
| **Automatic** (default) | `calendar.json` when it was synced in the last 24 hours, else Apple Calendar when allowed, else a stale `calendar.json` |
| **Google via Cursor** | `calendar.json` only |
| **Apple Calendar** | EventKit (needs the Calendar permission) |
| **None** | Nothing |

### Google Calendar through Cursor

When Apple Calendar is not available (for example on a managed Mac) and
Google's private iCal link is off, a Cursor agent can read Google Calendar
through an MCP server and write a local file. GrokNola only reads the file:
no Google sign-in and no network access in the app.

1. Install the skill: `mkdir -p ~/.cursor/skills && cp -R skills/grok-notes-calendar-sync ~/.cursor/skills/`
2. Connect a Google Calendar MCP server in Cursor Settings > MCP.
3. In Cursor, say **"Sync my calendar for GrokNola"**
   (Settings > Calendar & Drive > **Copy sync prompt** copies it).
4. To keep it fresh while Cursor is open: `/loop 30m sync my calendar for GrokNola`.

GrokNola watches the file and reloads it within a minute of a change.
Settings shows the status, for example "Google via Cursor · synced 12 min ago · 14 events".

### calendar.json contract

Path: `~/Library/Application Support/GrokNotes/calendar.json`
(override with the `GROK_NOTES_CALENDAR_FILE` environment variable for testing).
Writers must replace it atomically: write a temp file in the same folder, then rename it.

```json
{
  "version": 1,
  "source": "google-calendar-mcp",
  "syncedAt": "2026-11-04T20:00:00Z",
  "timeZone": "America/Los_Angeles",
  "rangeStart": "2026-11-03T00:00:00-08:00",
  "rangeEnd": "2026-11-12T00:00:00-08:00",
  "events": [
    {
      "id": "abc123",
      "title": "Pricing sync",
      "start": "2026-11-04T10:00:00-08:00",
      "end": "2026-11-04T10:30:00-08:00",
      "allDay": false,
      "attendees": [{"name": "Yemi A", "email": "yemi@example.com", "self": false, "response": "accepted"}],
      "organizer": {"name": "Yemi A", "email": "yemi@example.com"},
      "conferenceURL": "https://meet.google.com/abc-defg-hij",
      "location": "Room 4",
      "description": "Optional, truncated to 2000 characters"
    }
  ]
}
```

- Only `id`, `title`, `start`, and `end` are required.
- Times are ISO 8601 with an offset (fractional seconds allowed). All-day events use
  `YYYY-MM-DD` dates with an exclusive end, interpreted in `timeZone`.
- Events you declined (`self: true`, `response: "declined"`) are ignored. Entries that
  cannot be read are skipped and counted in the Settings status.
- The current meeting is the timed event that overlaps now (from 10 minutes before
  its start to its end), preferring events with other invitees. Invitee names come
  from `name`, else the email's local part; `self` is left out. A Meet, Zoom, or Teams
  `conferenceURL` names the meeting app when no running app was detected.

## Ask across notes

**Ask Grok** at the top of the sidebar (Command-K) is one chat over every meeting, and the app's built-in help (see [Help](#help)).
Grok ranks meetings by keywords, names, and recency, picks the most relevant ones from a
compact index, then answers from their notes and transcripts. Each answer links to its
source meetings; click a link to open the meeting. The search field above the meeting list
filters by title, notes, people, and transcript text. The chat history is saved in
`~/Library/Application Support/GrokNotes/library-chat.json`.

## Live answers

While recording, the **Answers** pane of the meeting inspector answers questions heard in the call.
The toolbar bolt button turns it on or off for the current recording; **Settings > Live Answers** sets the default.

- Questions are found on the Mac with local rules (`Sources/GrokNotes/LiveAnswers/QuestionDetector.swift`):
  a question mark, a leading question word or auxiliary plus a subject, or cues like "do you know".
  Small talk ("can you hear me", "does that make sense"), tag questions (", right?"), requests to a person
  ("can you send me…"), 4-word-or-shorter lines, and near-duplicates from the last 2 minutes are skipped.
- One request runs at a time, detected questions start at most every 8 seconds, and a newer question
  replaces a queued one or cancels a running one that has not streamed yet. The model can reply `SKIP`,
  and those cards are never shown.
- Each request streams from `grok-4.20-non-reasoning` (no reasoning phase) with the last 3 minutes of
  transcript, your rough notes, and up to 3 past meetings that match the question's keywords, capped at
  about 8,000 characters and 200 output tokens. Change the model, reasoning effort, and priority
  processing in **Settings > Models & API**.
- **Ask now** at the bottom of the pane sends a typed question the same way.
- Answers are in memory only. **Pin** appends the question and answer to your rough notes as a quote
  block, so they are saved and used in the enhanced notes. Unpinned answers are cleared when recording stops.
- Usage is logged as **Live answers** in Usage & Cost.

## Help

The user guide is `Resources/Help/GrokNotesGuide.md`. The build script copies it into
`GrokNola.app/Contents/Resources/Help/`; `swift run` reads the source copy. Ask how the app
works in **Ask Grok** (Command-K), **Help > GrokNola Help** (Command-?), or
**Settings > General > Ask about GrokNola**.

- A local keyword check routes each question. Clear app questions ("How do I sync Google Calendar?",
  "Why is system audio off?") are answered from the guide alone, with no meeting-selection request.
  Clear meeting questions skip the guide. Anything unclear gets both.
- Help answers give steps with the exact UI labels, say when the guide does not cover something, and can
  include links that open Settings (`groknotes://settings`), Usage & Cost (`groknotes://usage`), Home
  (`groknotes://home`), or a System Settings privacy pane (`groknotes://privacy/microphone`,
  `screen-recording`, `accessibility`, `calendars`).
- Help-only questions are logged in Usage & Cost as **Help questions**.

Keep the guide in step with this README when a feature changes.

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

1. Open Settings (Command-comma) → **Calendar & Drive**.
2. Turn on **Copy notes to Google Drive when saved**.
3. Optionally set a **Subfolder under My Drive** (for example `GrokNola`). Leave it blank to write at the top level of My Drive.

On each save, GrokNola copies `notes.md` and `meeting.json` into:

`~/Library/CloudStorage/GoogleDrive-<account>/My Drive/<subfolder>/<yyyy-MM-dd Meeting title>/`

Folder names use the meeting start date and a sanitized title. If Drive is not mounted, the app keeps saving locally and logs an export failure; it does not block saves or show an error banner.
