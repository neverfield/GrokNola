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
Build with Xcode 26 or later (macOS 26 SDK) so the app gets the macOS 26 window style; the build script warns on an older SDK.

Permissions are tied to the code signature. Run `./scripts/create-signing-cert.sh`
once in a terminal. It creates a self-signed certificate in a dedicated keychain,
`~/Library/Keychains/groknola-signing.keychain-db`, with its own password, and leaves
it locked. Each build asks for that password, unlocks the keychain only while it signs,
then locks it and restores your keychain search list. Rebuilds keep their permissions,
and other apps cannot sign as GrokNola without the password. The first build with the
new certificate needs Microphone, Screen & System Audio Recording, Accessibility, and
Calendar granted once more. Without the dedicated keychain, the build falls back to a
certificate in the login keychain (with a warning), else to ad hoc signing. Set
`CODESIGN_IDENTITY` to use another certificate.

The app is signed with the Hardened Runtime and only the entitlements in
`Resources/GrokNola.entitlements` (microphone and calendars).

Google Calendar sign-in needs an OAuth client, which the build reads from the environment or
`scripts/google-oauth.env`; see [One-time OAuth client setup](#one-time-oauth-client-setup).

The app icon is `Resources/AppIcon.icns`, built from `Resources/AppIcon-master.png` (shaped by `scripts/shape-icon.swift`; other concepts in `Resources/icon-options/`).

`Resources/Assets.xcassets` holds the amber `AccentColor` that native controls use. The build compiles it with `actool`, which needs Xcode's first-launch setup once per Mac (`sudo xcodebuild -runFirstLaunch`); without it the build warns and falls back to the system accent.

## Use

1. When a call starts, click **Start notes** (window, menu bar, or Shift-Command-R).
   The menu bar icon changes when it detects a meeting in Zoom, Teams, Meet, Slack, Webex, or FaceTime.
2. Type rough notes while you talk. The transcript fills in live, and a **Live** strip under the
   notepad shows the latest lines. Level meters in the bottom bar show that the mic and call audio
   are arriving; a meter turns red when a side has been silent for 20 seconds.
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
| The meeting app's "who is talking" indicator, read through Accessibility from the call window only and matched to speech timing | Accessibility + **Settings > Speakers > Read who is talking from the meeting app** (off by default) | Real names (`active speaker`) |
| Call-window snapshots read by Grok vision, only from a window titled as the call (Zoom Meeting, Huddle, Meet tab) | **Settings > Speakers > Identify speakers from meeting-window snapshots** (off by default) | Real names (`seen on screen`) |
| Calendar invitees plus Grok reading the transcript for introductions and name use | A calendar source (optional, see [Calendar](#calendar)) | Real names (`inferred`) with a confidence bar |
| Your corrections | None | Saved, and matched on this Mac in later meetings (never sent to xAI) |

A speaker without strong evidence stays **Them**, so you fall back to Me / Them
when permissions are missing or the app is not supported. Without system audio,
the microphone alone is diarized and the main voice is labeled as you.

The active-speaker patterns in `Sources/GrokNotes/Speakers/ActiveSpeakerMonitor.swift`
are heuristics. Meeting apps change their labels, so add a pattern there if names stop appearing.
The monitor restores the meeting app's `AXManualAccessibility` / `AXEnhancedUserInterface` when recording
stops and does not poll while the recording is paused. Call-window titles live in `MeetingDetector.callWindowHints`.

## Security and privacy defaults

- **Capture scope.** With a detected meeting app, system audio comes only from that app and its helper
  processes (`SCContentFilter(display:including:exceptingWindows:)` in `Audio/SystemAudioCapture.swift`).
  Without one, it is all audio except GrokNola's, and the log says so.
- **Consent reminder.** When an invite lists anyone outside your company domains (Settings > Privacy & Data),
  a warning asks you to tell everyone and get consent (`ConsentReminder.swift`).
- **Prompts.** Transcripts, notes, titles, and names go into prompts inside tags such as `<transcript>`
  (`PromptData.swift`), with a rule that tagged text is data, not instructions, and that no links may be added.
  Titles and names are one line, at most 200 characters.
- **Key terms.** Transcription key terms are this meeting's invitees and your name only (at most 40), since
  the streaming request carries them in its URL.
- **Models and key.** Only the models in `Prefs.notesModels` are used; any other stored id falls back to the
  default. The xAI key is read only from the Keychain.
- **Links.** The link dialog names the host or mail recipient, shows the full address, warns on long
  addresses, and opens mail links without `body`, `cc`, or `bcc` (`LinkPolicy.swift`).
- **Network.** One ephemeral `URLSession` with no cache, cookies, or credential store and TLS 1.2+
  (`Network.swift`) serves xAI and Google.
- **Notifications** never include a meeting's title or content.

## Calendar

GrokNola uses your calendar to title a meeting, list its invitees, and show
**Up next** on Home (today's remaining events with **Join** and **Start notes**).
Pick the source in **Settings > Calendar & Drive**:

| Source | Reads |
| --- | --- |
| **Automatic** (default) | Google Calendar when connected, else Apple Calendar when allowed |
| **Google Calendar** | Your primary Google Calendar, through the app's own sign-in |
| **Apple Calendar** | EventKit (needs the Calendar permission) |
| **None** | Nothing |

### Google Calendar sign-in

**Settings > Calendar & Drive > Connect Google Calendar** signs in entirely on this Mac
(`Sources/GrokNotes/Speakers/GoogleOAuth.swift`): the system browser opens Google's consent page,
which redirects to a one-time listener on `127.0.0.1` (OAuth 2.0 for installed apps, with PKCE and a
`state` check). There is no backend and no web view.

- Scope: `calendar.events.readonly`, plus `openid email` to show the account.
- The refresh token is a Keychain item (service `dev.local.groknotes`, account `google_refresh_token`).
  Access tokens and events stay in memory and are never written to disk.
- Events from 6 hours ago through the end of tomorrow are fetched from the primary calendar every
  5 minutes, on wake, and on **Reload** (`GoogleCalendarSource.swift`). Cancelled and declined events
  are left out. **Disconnect Google** revokes the grant at Google and deletes the Keychain item.
- The current meeting is the timed event that overlaps now (from 10 minutes before its start to its
  end), preferring events with other invitees. A Meet, Zoom, or Teams link names the meeting app when
  no running app was detected.

#### One-time OAuth client setup

The repo has no OAuth client. To build with Google sign-in:

1. In a Google Cloud project owned by your organization, enable the **Google Calendar API**.
2. Configure the OAuth consent screen with user type **Internal**, so only accounts in your Workspace
   can sign in and no Google verification is needed. Add the scope `.../auth/calendar.events.readonly`.
3. Create an OAuth client ID of type **Desktop app**.
4. Give `scripts/build-app.sh` its ID and secret, either as environment variables or in the gitignored
   `scripts/google-oauth.env`:

   ```
   GROKNOLA_GOOGLE_CLIENT_ID=1234-abc.apps.googleusercontent.com
   GROKNOLA_GOOGLE_CLIENT_SECRET=GOCSPX-...
   ```

The script writes them into the built `Info.plist` only (`GNGoogleClientID`, `GNGoogleClientSecret`).
Google does not treat a desktop client's secret as confidential; PKCE protects the sign-in. Without
them the build still works and Settings says Google sign-in is not configured.

Older versions read a `calendar.json` written by a Cursor agent. GrokNola deletes that file at launch.

## Ask across notes

**Ask Grok** at the top of the sidebar (Command-K) is one chat over every meeting, and the app's built-in help (see [Help](#help)).
Grok ranks meetings by keywords, names, and recency, picks the most relevant ones from a
compact index, then answers from their notes and transcripts. Each answer links to its
source meetings; click a link to open the meeting. The search field above the meeting list
filters by title, notes, people, and transcript text. The chat history is saved in
`~/Library/Application Support/GrokNotes/library-chat.json`.

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
(`meeting.json.enc`, the audio as `mic.wav.enc` and `system.wav.enc` if you choose to keep it, and `frames/`).
These files are encrypted at rest with AES-GCM (`Sources/GrokNotes/Vault.swift`). The key is a Keychain item
(service `dev.local.groknotes`, account `vault_key`). Audio stays plain only until the after-call pass ends,
and plain files left by older versions or a crash are sealed at launch.
Audio and text leave the Mac only to reach `api.x.ai`, plus the notes-only Drive copy below.
**Export Transcript and Audio…** writes readable copies to a folder you choose.

### Google Drive (optional)

With **Google Drive for desktop** installed and signed in, you can mirror exports into synced **My Drive**:

1. Open Settings (Command-comma) → **Calendar & Drive**.
2. Turn on **Copy notes to Google Drive when saved**.
3. Pick the **Drive account**, or leave **Match my Google sign-in**: the mount whose email matches the Google
   Calendar sign-in, else the only one in your company domains. With no match, nothing is copied. A picked
   account is never replaced by another mount.
4. Optionally set a **Subfolder under My Drive** (for example `GrokNola`). Leave it blank to write at the top level of My Drive.
   Dot-only names are refused, and leading dots become `_`.

On each save after recording stops (never during a recording), GrokNola writes the notes without the transcript (`Meeting.notesMarkdown`) as `notes.md` into:

`~/Library/CloudStorage/GoogleDrive-<account>/My Drive/<subfolder>/<yyyy-MM-dd Meeting title>/`

Folder names use the meeting start date and a sanitized title. If Drive is not mounted, the app keeps saving locally and logs an export failure; it does not block saves or show an error banner.

## Design system

The look comes from the app icon: a cream page, graphite ink, and an amber waveform. System
chrome (sidebar, toolbar, inspector, materials) stays native; the identity lives in the content.
Tokens are in `Sources/GrokNotes/Views/DesignSystem.swift`, components in `Views/Components.swift`,
and speaker, chapter, and tag colors in `Views/Palettes.swift` and `Tags.swift`. Colors resolve per
appearance, with stronger ink and borders under Increase Contrast.

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `paper` | `#FBF8F1` | `#1C1B19` | Notes, transcript, answers, Home |
| `paper2` | `#F4EFE4` | `#252320` | Panels, side columns |
| `ink` | `#1F2124` | `#ECE8DF` | Primary text |
| `inkMuted` | `#655F55` | `#ABA497` | Secondary text (instead of `.secondary`) |
| `inkFaint` | `#8C8476` | `#7F786D` | Placeholders and decoration only |
| `hairline` | `#E4DCCB` | `#38342E` | Borders and rules |
| `accent` | `#B8741A` | `#C7832A` | `.tint` on every scene: buttons, toggles, selection |
| `amberText` | `#94590E` | `#F0B867` | Links on the paper |
| `amber` / `amberSoft` | `#E8A33D` / `#F5E2BF` | `#EBA94A` / `#45361F` | Waveform mark, playhead / citation pills, matches |
| `recording` | `#BE3F2C` | `#EF6B57` | Recording only |

Text tokens meet WCAG AA (4.5:1) on `paper` and `paper2` in both modes; `inkFaint` (3.5:1) is
not used for content.

- **Type** (`GrokTypography`): Grok's writing and titles use New York (`display` 30, `title` 22,
  notes body 15 with about 1.45 line height, measure 680 points). Controls stay SF Pro (`heading`,
  `body`, `secondary`, `meta`). Times and counts use monospaced digits.
- **Components**: `GrokPanel` (paper 2, hairline, 12-point corners), `GrokChip` (speaker, tag, and
  topic chips), `GrokSectionHeader`, `GrokEyebrow`, `GrokBar`, `GrokComposer` (the ask field),
  `ChatTurnView`, `GrokEmptyState`, `GrokLinkButtonStyle`, and `WaveformMark`, the icon's amber
  waveform. Use the mark sparingly: the sidebar wordmark, empty states, Home, and live states.
- **Speakers** take earthy colors in speaking order (slate, terracotta, plum, teal, ochre, indigo,
  clay); you are sage. Chapters use a quieter ramp of the same family.
