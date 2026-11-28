# GrokNola

GrokNola is a Granola-style meeting notepad for macOS that runs entirely on the xAI API. No bot joins your call.
It listens to your microphone and your Mac's call audio and transcribes as people talk, with
`grok-voice-transcribe-2.0`. When the call ends, it uses `grok-4.7` to turn your rough notes and the transcript
into clean notes, with named speakers, action items, and timestamps that link back to what was said.

- **No bot in the meeting.** It works with Zoom, Teams, Google Meet, Slack huddles, Webex, and FaceTime by
  listening on your Mac.
- **Your notes stay the backbone.** Grok keeps every point you typed, in your order, and adds specifics from the
  transcript.
- **Every point is cited.** Bullets end with timestamps such as **5:17**. Click one to see that moment in the
  transcript, or to hear it if you keep the audio.
- **Ask across meetings.** One chat (Command-K) answers from all your notes and transcripts, and links to the
  meetings it used.
- **Private by default.** Meetings are encrypted on your Mac, and audio and text go only to `api.x.ai`. A consent
  check runs before every recording.

You use your own xAI API key. GrokNola shows what each meeting costs.

## Install

1. Download `GrokNola-X.Y.Z.zip` from [Releases](https://github.com/neverfield/GrokNola/releases), unzip it, and
   move **GrokNola** to Applications. Releases are signed and notarized by Apple; to check one, see
   [Verify a download](#verify-a-download).
2. Open GrokNola, open Settings (Command-comma), and paste your xAI API key. It is stored in the Keychain.
3. Grant **Microphone** and **Screen & System Audio Recording** when asked, then relaunch GrokNola.
   **Calendar** is optional. It gives meetings their titles and invitees.

GrokNola needs macOS 14 or later on an Apple silicon Mac. To build it yourself, see
[Build from source](#build-from-source).

## A walkthrough

Everything in this example is made up: the people, the company, and the call.

### Before the call

Your calendar has **Northwind onboarding kickoff** at 10:00 on Zoom. You're meeting Dana Reyes
(`dana@northwind.example`), the customer, and Yemi Adeyemi, a colleague. At 9:58, Home lists it under **Up next**,
with **Join** and **Start notes**.

Click **Join** to open Zoom, then click **Start notes**. Dana's domain is outside your company domains, so GrokNola
asks first. The dialog says "Everyone in this meeting knows you're taking AI notes and agreed where the law requires
it." and names `northwind.example`. Click **Start Notes** to begin.

### During the call

Type rough notes as you talk. They don't need to be tidy:

```text
go-live date?
SSO - they use okta
import from old tool, ~40k records
dana owns rollout, training for 12 ppl
```

The transcript fills in as people speak. Under the notepad, the **Live** strip shows the latest line from each side:

```text
Dana Reyes   We'd like to be live before the end of March, ideally the week of the 17th.
You          That works if we have the import file two weeks ahead.
```

Level meters in the bottom bar show that both your mic and the call audio are arriving.

### After the call

Click **Stop & Write Notes** (Shift-Command-R). The Notes tab shows each step as it runs: **Transcribing full
recording**, **Naming speakers**, **Writing notes**, and **Tagging**. Dana's name comes from the invite and from
her introducing herself on the call. Then the notes appear. With the **General meeting** template, they read:

```markdown
# Northwind onboarding kickoff

## Summary
Kickoff to plan Northwind's rollout. The team agreed to go live the week of March 17, provided the
import file arrives by March 3. Single sign-on and training were planned. Archived records are undecided.

## Key points by topic
### Timeline
- Northwind wants to go live the week of March 17 [03:12]
- The date holds only if the import file arrives two weeks ahead [03:40] [04:05]

### Single sign-on
- Northwind uses Okta, and SSO must be on before training starts [06:18]

### Data import
- About 40,000 records move from their current tool as a CSV export [08:51] [09:30]
- Custom fields need checking before the import [10:02]

### Training
- Dana owns the rollout and needs training for 12 people [12:44]

## Decisions
- Go-live is the week of March 17 [14:20]
- Training runs as two sessions of six people [15:02]

## Action items
- [ ] Dana Reyes: send the import file, by March 3 [04:05]
- [ ] Yemi Adeyemi: send the Okta SSO setup guide, by Friday [06:55]
- [ ] You: book the two training sessions [15:10]

## Open questions
- Whether archived records need importing too [11:37]
```

In the app, the timestamps show as pills. **3:12** opens the transcript where Dana gave the date. If you keep the
audio, the pill reads **▶ 3:12** and plays that moment. Each line of your rough notes is still there, now with
the details from the call. Check off an action item when it's done, or click **Edit** to fix a line. GrokNola also
tags the meeting, for example **Onboarding**.

Beside the notes, the **call summary** shows the length of the call, each speaker's share of the talking (for
example Dana 46%, You 31%, Yemi 23%), and chapters such as **Timeline** at 2:50 and **Data import** at 8:30.
Click a chapter to jump to it.

### The transcript

The **Transcript** tab (Command-2) shows who said what, split into chapters. **Copy Transcript** gives you text like:

```text
## Timeline (02:50–06:05)
[03:12] Dana Reyes: We'd like to be live before the end of March, ideally the week of the 17th.
[03:40] You: That works if we have the import file two weeks ahead.
[04:05] Dana Reyes: I can get it to you by March 3.
```

If a name is wrong, click it and type the right one. GrokNola remembers the correction for later meetings.

### Ask

Use the meeting's **Ask** tab (Command-3) for this meeting alone, for example "Draft a short follow-up email to Dana
with the dates we agreed." Use **Ask Grok** (Command-K) to ask across every meeting:

> **You:** What did Northwind commit to, and by when?
>
> **Grok:** Dana Reyes will send the import file by March 3, and Northwind plans to go live the week of March 17.
> Source: *Northwind onboarding kickoff*

Click the source to open the meeting. Ask Grok also answers questions about GrokNola itself, such as "Why is system
audio off?"

### Afterwards

The meeting stays on your Mac, encrypted. By default the audio is deleted once the notes are written; turn on
**Keep audio recordings after notes are written** in Settings to keep it for playback. Each meeting's header shows
what it cost, and **Usage & Cost** (Shift-Command-U) shows the totals.

The rest of this README is the full reference. The in-app guide (Command-?) covers the same features step by step.

## Build from source

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
   in the bar that appears, or press Command-Z. The trash is emptied of meetings older than 30 days at launch,
   except under legal hold.
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
- **Before recording.** Every Start Notes path goes through `AppState.startMeeting`, which checks, in order:
  - **Blocked domains.** Invitees at `Prefs.blockedDomains` (empty by default, subdomains included, plus any set
    at build time) always refuse recording: "GrokNola doesn't record meetings with people at blocked
    domains." (`RecordingPolicy.swift`)
  - **Recording scope.** `Prefs.recordingScope` is `.warnExternal` by default: outside invitees force the consent
    confirmation. `.internalOnly`, the strictest setting, refuses any outside invitee and requires the confirmation when
    there is no invite. `.any` leaves it to the consent settings.
  - **FileVault.** The data folder's `volumeIsEncrypted` is trusted when true; otherwise `fdesetup status` decides,
    since the APFS value can read false on a FileVault-protected Apple silicon volume. Off or unknown warns, and a
    pilot build refuses (`DiskEncryption.swift`).
  - **Consent confirmation.** On by default (`Prefs.consentConfirmation`): "Everyone in this meeting knows you're
    taking AI notes and agreed where the law requires it.", naming outside domains. **Start Notes** or **Cancel**.
    `Meeting.consentConfirmedAt` and `Meeting.externalDomains` record it. "Don't ask again" is offered only for
    invites whose invitees are all in your company domains.
- **Consent reminder.** When an invite lists anyone outside your company domains (Settings > Privacy & Data) and
  the confirmation was not shown, a warning asks you to tell everyone and get consent (`ConsentReminder.swift`).
- **Retention.** `Prefs.textRetentionDays` (Never by default; 30, 90, 180, 365) deletes meetings by `startedAt`
  at launch, next to the audio retention (`Retention` in `LegalExport.swift`).
- **Legal hold.** `Prefs.legalHold` suspends every deletion: meeting and audio retention, `MeetingTrash.purge`,
  and permanent deletes. Recordings are sealed and kept after the notes are written even with Keep audio off
  (`Retention.shouldKeepAudio`). Delete still moves a meeting to the trash, with a message; Forget person is refused.
- **Export all for Legal…** (Settings > Privacy & Data) writes every meeting, the trash included, as `notes.md`,
  `transcript.txt`, `meeting.json`, and kept audio, plus `manifest.json` with each meeting's id, title, `startedAt`,
  and each file's name, size, and SHA-256 (`LegalExport.swift`). The copies are plain text.
- **Forget person…** (Settings > Speakers) removes a name from remembered people and from every meeting's
  speakers, case-insensitively. Transcript text, notes, and invitee lists are left alone.
- **Sealed sidecars.** Remembered people (`known-people.json.enc`, moved once from UserDefaults), `tags.json.enc`,
  `templates.json.enc`, and `library-chat.json.enc` are sealed by `Vault`. `usage.jsonl` keeps meeting ids only;
  titles are looked up when shown, and older lines are rewritten without them.
- **Drive policy.** `Prefs.allowDriveExport` (default true) gates the Drive copy and its Settings. Turn it off with
  `defaults write com.neverfield.groknola allowDriveExport -bool false`.
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

### Pilot builds

To make a pilot build:

```bash
GROKNOLA_PILOT=1 GROKNOLA_BLOCKED_DOMAINS="example.org example.net" ./scripts/build-app.sh
```

The script writes `GNPilotBuild` = true into the signed `Info.plist`. The app then turns off the Drive copy, uses
`.internalOnly`, keeps snapshots and Accessibility speaker reading off, forces the consent confirmation on every
recording, and refuses to record without FileVault (`PilotBuild.swift`). Settings shows those switches disabled
with "Set by the pilot build." `GROKNOLA_PILOT=1 swift run` previews the same locks; neither the key nor the
variable can turn them off.

`GROKNOLA_BLOCKED_DOMAINS` (any build) writes `GNBlockedDomains`, domains the build always blocks on top of the
Settings list. The script warns when a pilot build has none.

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
`~/Library/Application Support/GrokNotes/usage.jsonl`, which names meetings by id only.

## Data

Everything lives in `~/Library/Application Support/GrokNotes/Meetings/<id>/`
(`meeting.json.enc`, the audio as `mic.wav.enc` and `system.wav.enc` if you choose to keep it, and `frames/`).
These files are encrypted at rest with AES-GCM (`Sources/GrokNotes/Vault.swift`). The key is a Keychain item
(service `dev.local.groknotes`, account `vault_key`). Audio stays plain only until the after-call pass ends,
and plain files left by older versions or a crash are sealed at launch.
Audio and text leave the Mac only to reach `api.x.ai`, plus the notes-only Drive copy below.
**Export Transcript and Audio…** writes readable copies to a folder you choose.

### Google Drive (optional)

Pilot builds, and `allowDriveExport` set to false, turn this off. Otherwise, with **Google Drive for desktop**
installed and signed in, you can mirror exports into synced **My Drive**:

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

## Releases

Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`. It runs the tests, then waits for a reviewer to
approve the `release` environment, which holds every signing secret. After approval it builds with
`GROKNOLA_RELEASE=1`, signs with the Developer ID certificate in a temporary keychain (deleted right after),
notarizes and staples, publishes `GrokNola-X.Y.Z.zip` with its SHA-256, and records a build provenance
attestation. Releases are immutable, so published files can't be replaced.

Release mode in `scripts/build-app.sh` refuses pilot settings, because anyone can read a release's `Info.plist`.
Make pilot builds locally. It also fails unless the signature is Developer ID, from `APPLE_TEAM_ID`, with the
Hardened Runtime, a secure timestamp, and exactly the entitlements in `Resources/GrokNola.entitlements`.

### Cut a release

Merge to `main` through a pull request, then:

```bash
git switch main && git pull
git tag v0.2.0 && git push origin v0.2.0
```

Approve the run in the repository's Actions tab. The workflow refuses tags that aren't on `main`.

### One-time setup

1. In the Apple Developer portal, create a **Developer ID Application** certificate. Export it from Keychain
   Access as a `.p12` with a long random password, and keep a copy in your password manager.
2. In App Store Connect > Users and Access > Integrations, create a team API key with the **Developer** role and
   download the `.p8`.
3. Store them in the `release` environment. `gh secret set` without `--body` prompts, so values stay out of shell
   history:

   ```bash
   base64 -i DeveloperID.p12 | gh secret set DEVELOPER_ID_P12_BASE64 --env release
   gh secret set DEVELOPER_ID_P12_PASSWORD --env release
   gh secret set NOTARY_API_KEY_P8 --env release < AuthKey_KEYID.p8
   gh secret set NOTARY_API_KEY_ID --env release
   gh secret set NOTARY_API_ISSUER_ID --env release
   gh variable set APPLE_TEAM_ID --env release --body YOURTEAMID
   ```

   Then delete the `.p12` and `.p8` files from Downloads.
4. Optional: to turn on Google Calendar sign-in in releases, also set `GROKNOLA_GOOGLE_CLIENT_ID` and
   `GROKNOLA_GOOGLE_CLIENT_SECRET` the same way. Without them, releases ship with Google sign-in off, and the
   calendar comes from Apple Calendar.

The release job checks the certificate password, team, and notary key before it builds, so wrong values fail
in seconds with a message that names the secret.

### Verify a download

```bash
shasum -a 256 -c GrokNola-0.2.0.zip.sha256
gh attestation verify GrokNola-0.2.0.zip --repo neverfield/GrokNola
spctl --assess --type execute --verbose GrokNola.app   # expect "source=Notarized Developer ID"
```

### Moving from a local build

Releases use the bundle ID `com.neverfield.groknola`. The first launch copies settings from the old
`dev.local.groknotes` domain. Keychain items keep the old service name, but macOS asks once whether the newly
signed app may read them. Choose **Always Allow**. Denying the `vault_key` prompt leaves sealed meetings
unreadable until you allow it. Microphone, Screen & System Audio Recording, Accessibility, and Calendar need
granting once more.

### If a signing secret leaks

1. Revoke the Developer ID certificate in the Apple Developer portal. Gatekeeper then rejects apps signed with
   it, so also ship a release signed with a new certificate.
2. Revoke the App Store Connect API key.
3. Replace the `release` environment secrets, and review recent runs in the Actions tab.

The Developer ID certificate expires after 5 years. Renew it a few months early.
