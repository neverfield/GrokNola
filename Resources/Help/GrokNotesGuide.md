# Grok Notes user guide

Grok Notes is a meeting notepad for macOS. No bot joins your call. The app listens to your microphone and to your Mac's audio, transcribes live with `grok-voice-transcribe-2.0`, and writes notes with `grok-4.7`. Everything runs on the xAI API with your own API key.

## Getting started

1. Open **Settings** (Command-comma, or **Settings** in the menu bar menu).
2. In the **Models & API** pane, under **xAI API**, paste your key into **API key** and click **Save key**. The key is stored in the macOS Keychain. Click **Test connection** to check it. ("Connected. N models available." means it works.) The app also reads an `XAI_API_KEY` environment variable when no key is saved.
3. In the **General** pane, under **You**, check **Your name**. It defaults to your macOS account name. The app uses it for your speaker label and never gives your name to another speaker.
4. In the **Recording** pane, under **Permissions**, click **Allow** next to each permission you want (see [Permissions](#permissions)). After you grant **Screen & System Audio Recording**, click **Relaunch Grok Notes**.
5. Click **Refresh status** to update the check marks.

Home also shows a setup checklist (xAI API key, Microphone, Screen & System Audio Recording, Accessibility, Calendar) with an **Open Settings** link until you have recorded a meeting.

## Permissions

Grok Notes asks for four macOS permissions. Only the microphone is required.

| Permission | Why it matters | Without it |
| --- | --- | --- |
| **Microphone** | Records your voice. | You cannot start notes. |
| **Screen & System Audio Recording** | Records the other participants from your Mac's audio, on a separate stream from your mic. Also lets the app read meeting window titles (meeting detection) and take window snapshots for speaker names. | Microphone only. Everyone is mixed together, and remote speakers are harder to separate. |
| **Accessibility** | Reads the meeting app's "who is talking" indicator, so remote speakers get real names. | Names come only from snapshots, the transcript, and your corrections. Often Me / Them. |
| **Apple Calendar** | Meeting title and invitees from Apple Calendar, when Apple Calendar is the calendar source. | Use Google via Cursor, or no calendar. |

To grant a permission:

1. Open **Settings > Recording** and click **Allow**. macOS shows a prompt, or opens **System Settings > Privacy & Security**.
2. In System Settings, turn on **Grok Notes** in the matching list (**Microphone**, **Screen & System Audio Recording**, **Accessibility**, or **Calendars**).
3. For Screen & System Audio Recording, click **Relaunch Grok Notes** (or quit and reopen the app). macOS applies it only on relaunch.

### Keep permissions across rebuilds

macOS ties privacy permissions to the app's code signature. If you build the app yourself, run `./scripts/create-signing-cert.sh` once. It creates a local certificate named "Grok Notes Local Signing" in your login keychain, and `./scripts/build-app.sh` signs every build with it, so rebuilds keep their permissions. Set `CODESIGN_IDENTITY` to use another certificate. Without a certificate, the build is signed ad hoc, the signature changes on every build, and macOS forgets the permissions.

## Recording a meeting

### Start

Click **Start notes** when the call begins. You can start from:

- The **Start notes** button at the bottom of the sidebar, or in the window toolbar.
- The **Start notes** button at the top of **Home**.
- **Start notes** next to an event in **Up next** on Home. The meeting gets that event's title and invitees.
- The menu bar icon > **Start Notes** (or **Start Notes · Zoom** when a call is detected).
- **Meeting > Start Notes** (Shift-Command-R).

When a meeting app is in a call, the buttons read **Start notes · Zoom** (or the app's name).

When you start, the app uses the current calendar event (from 10 minutes before its start to its end) for the title and invitees. Without an event, the title is the app name and time, and Grok replaces it with a title from the notes when they are written. A title you type yourself is never replaced.

### Meeting detection

Every few seconds, the app checks for a call in Zoom, Microsoft Teams, Slack (huddles), Webex, FaceTime, or Google Meet in a browser (Chrome, Safari, Arc, Edge, Brave, Firefox, Vivaldi). When it finds one, the menu bar icon changes and the menu offers **Start Notes · <App>**. Detection never starts recording by itself.

The first time a call is detected, macOS asks whether Grok Notes may send notifications. If you allow it, a notification "<App> call detected — Start notes for this call?" appears once per call; click **Start Notes** on it to begin. If you deny it, nothing else changes. To turn this notification off, run `defaults write dev.local.groknotes notifyOnMeetingDetected -bool false` and relaunch.

- Google Meet is found from the browser tab title, which needs **Screen & System Audio Recording**.
- With that permission, Zoom and Slack count only when a call window is open ("Zoom Meeting", "Huddle"). Otherwise an app counts while another app is using the microphone.

### While recording

- Type rough notes in the notes editor ("Jot rough notes here while you talk…"). Short phrases are fine. They become the backbone of the enhanced notes.
- Under the notepad, a **Live** strip shows the last thing heard from **Them** and **You**. Click **Live** to collapse or expand it; the app remembers your choice.
- The **Transcript** tab shows the live transcript. A **Live** box shows the words being heard now, labeled **Them** and **Me**. If you scroll up, click **Jump to latest** to follow again.
- A bar at the bottom of the window shows the elapsed time, a level meter for your microphone and one for call audio, and **Stop & Write Notes**. The bars move when sound arrives, so you can see that both sides are being captured.
- A meter turns orange when that side looks silent: your mic has had no signal for 20 seconds while others talk, or there has been no call audio for 20 seconds while you talk. Hover over it for the reason. See [No audio from your mic, or no call audio](#no-audio-from-your-mic-or-no-call-audio).
- If the transcription connection drops, an orange "Transcription reconnecting" message appears next to the meters. The app reconnects by itself.
- The menu bar menu shows the meeting title, the elapsed time, **Open Notes**, and **Stop & Write Notes**.

### Live answers

While recording, the inspector on the right opens to **Answers** (switch to **Info** for tags and speakers). When someone in the call asks a question, a card shows who asked, when, and a short answer from Grok.

- Turn it off or on for this recording with the **Live answers** bolt button in the toolbar. Set the default in **Settings > Live Answers > Answer questions heard during calls**.
- Small talk ("Can you hear me?", "Does that make sense?") and repeats from the last 2 minutes are ignored. Grok also skips questions that need no answer.
- Answers use the last few minutes of the transcript, your rough notes, and matching past meetings, which are named in a **From** line.
- Type in **Ask now…** at the bottom of the pane for a quick question of your own.
- **Pin** adds the question and answer to your rough notes, so they are kept and used in the enhanced notes. **Unpin** removes them. **Copy** copies them. **Dismiss** removes the card.
- Answers are not saved unless pinned. Unpinned cards are cleared when you stop.
- **Settings > Live Answers** also sets **Include relevant past meetings** and **Show answer latency**. **Settings > Models & API** sets the **Live answers model**, **Reasoning effort** (shown only for models that reason), and **Priority processing**.

### Stop

Click **Stop & Write Notes** in the bottom bar, use **Meeting > Stop & Write Notes** (Shift-Command-R), or the menu bar menu > **Stop & Write Notes**. Then the app:

1. Re-transcribes the full recording with diarization, so speaker numbers are stable for the whole meeting. If this pass fails, the live transcript is kept.
2. Names the speakers (see [Speaker names](#speaker-names)).
3. Writes enhanced notes with the meeting's summary template.
4. Finds topics and chapters.
5. Adds tags, when automatic tagging is on.

The Notes tab shows these steps as they run: **Transcribing full recording**, **Naming speakers**, **Writing notes**, and **Tagging**. Each step shows a check mark when done, a spinner while it runs, an empty circle while it waits, or an orange mark when it failed. While Grok writes, the notes area shows the headings of the meeting's template with placeholder lines. Switch to **My notes** to see your rough notes. The sidebar row shows a spinner.

If a step fails, the reason appears under the steps. Click **Retry** to run only that step again (writing notes, naming speakers, or tagging). The full-recording pass cannot be retried; the live transcript is kept. Click the close button to hide the steps.

If you stop without any transcript or notes, a message says "Nothing was recorded, so the meeting was discarded."

### Notifications

When processing finishes and you are not looking at that meeting, a notification says "Notes ready — <title>". Click it to open the meeting. If writing the notes failed, the notification says so instead, and the meeting keeps its step list with **Retry**. Notifications need permission, which macOS asks for the first time one is sent. Change it later in **System Settings > Notifications > Grok Notes**.

### Messages

Messages appear across the top of the window. Blue messages are information and close by themselves. Orange messages are warnings, and red messages are errors; they stay until you close them. Some have a button, such as **Open Settings** when the API key is missing. At most two show at once; "N more messages" and **Dismiss All** appear when there are more.

## Speaker names

Your microphone and your Mac's audio are recorded on separate streams. Your mic is **you**. The system audio is diarized (split by voice) into remote speakers. Then the app puts names on remote speakers from this evidence, strongest first:

1. **Your corrections.** A name you set is never overwritten.
2. **Active speaker** (needs Accessibility and system audio). While you record, the app reads the meeting app's accessibility labels once a second, such as "Talking: Ana" or "Ana is speaking". A voice gets a name when that name was shown in at least 3 samples and in 60% or more of the samples during that voice's speech. Label: "active speaker".
3. **Window snapshots** (needs Screen & System Audio Recording). While remote participants talk, the app saves a snapshot of the meeting window every 4 seconds. After the meeting, Grok vision reads the highlighted tile and participant names. It accepts a name at 70% confidence or more. The snapshots are sent to xAI and deleted after processing. Label: "seen on screen". Turn this off in **Settings > Speakers > Identify speakers from meeting-window snapshots**.
4. **One-on-one rule.** When there is exactly one remote voice and exactly one other invitee (or one other participant visible in the call window), that voice gets that name.
5. **Transcript inference.** Grok reads the transcript for introductions ("This is Dana from finance") and people addressed by name, matched against calendar invitees, names seen in the meeting app, and people from past meetings. It needs 75% confidence for a known name and 85% for any other name. Label: "inferred by Grok". Turn this off in **Settings > Speakers > Let Grok infer names from the conversation**.

A remote speaker without strong evidence stays **Them**. When permissions are missing or the app is not supported, you fall back to Me / Them. Without system audio, the microphone alone is diarized and the voice that talks most is labeled as you.

### Rename a speaker

1. Click a speaker name: in the transcript, in the call summary, or in **Meeting info** (the info button in the toolbar) > **Speakers**.
2. In "Who is this?", type a name or click a suggestion (invitees and remembered people).
3. Click **Save**. **Clear name** goes back to Me or Them.

Names you set, and names confirmed by the active speaker or snapshots, are remembered. They help name speakers and spell names in later meetings. **Settings > Speakers** shows the count under **Remembered people**.

**Meeting info > Attribution > Mode** shows how a meeting was named: **Identifying speakers** (still working), **Named speakers**, **Me / Them**, or **Microphone only** (system audio was off). Each speaker shows its source and confidence, for example "active speaker 92%". Hover a name to see the evidence.

The active-speaker labels are heuristics for each meeting app. When a meeting app changes its labels, names can stop appearing until the patterns are updated.

## Notes

Each meeting has three tabs in the toolbar, next to the title: **Notes**, **Transcript**, and **Ask** (Command-1, Command-2, Command-3, or **View > Notes / Transcript / Ask**).

### Rough notes and enhanced notes

- Before and during the meeting, the Notes tab is a plain editor for your rough notes.
- After the meeting, Grok writes **enhanced notes**: your rough notes kept in order, filled in with specifics from the transcript, in the sections of the summary template.
- Use the **Enhanced** / **My notes** switch at the top left of the notes to go between them. You can keep editing your rough notes.
- You can select and copy enhanced notes across lines. Copied text keeps bullets, checkboxes, and timestamps as Markdown, such as `- [ ] ` and `[05:17]`.
- Click a checkbox in the enhanced notes to mark an action item done or open.
- To fix a name or a line, click **Edit** at the top right of the notes (or **Edit Notes** in the **More** menu). The notes show as Markdown with light styling. Type your changes. They save by themselves. Click **Done** to see the formatted notes again. Editing is off while Grok writes notes. **Regenerate** replaces your edits with new notes.

### The More menu and Share

The **More** button (**…**) in the meeting toolbar has:

- **Regenerate Notes** (Option-Command-R) writes the enhanced notes again, for example after you add rough notes or rename speakers. It reads **Write Notes** when a meeting has no enhanced notes yet. **Regenerate with <template>** appears when you picked another template.
- **Edit Notes**.
- **Copy Markdown** (Shift-Command-C) copies the whole meeting (title, attendees, call summary, notes, transcript) as Markdown.
- **Copy Transcript** copies the transcript as plain text (see [Transcript](#transcript)).
- **Find in Transcript** (Command-F in the Transcript tab).
- **Show in Finder** opens the meeting's `notes.md`.
- **Delete Meeting** (see [Delete and undo](#delete-and-undo)).

**Share** (next to **More**) sends the same Markdown to Mail, Messages, Notes, or another app. The **Meeting** menu has **Copy Markdown**, **Regenerate Notes**, and **Find in Transcript** too. **Meeting info** (Option-Command-I) opens the inspector.

### Summary templates

A template decides the sections and focus of the enhanced notes. Built-in templates:

- **General meeting**: Summary, Key points by topic, Decisions, Action items, Open questions.
- **Customer / sales call**: Context, Their needs & pain points, Objections & concerns, What we committed, Next steps, Deal signals.
- **1:1**: Updates, Feedback (both ways), Blockers, Goals & growth, Action items.
- **Standup / team sync**: Updates by person, Decisions, Follow-ups.
- **Brainstorm / planning**: Problem framing, Ideas, Promising directions, Open questions, Next experiments.

To pick a template for one meeting:

1. Open the meeting. Click the template menu at the top left of the notes. It reads **Written with: <template>** after notes are written, and **Template: <template>** before.
2. Choose a template. You can do this before, during, or after the call.
3. If the notes were already written with another template, click **Regenerate with <template>** next to the menu. Changing the template does not rewrite the notes by itself.

Meetings without a choice use the default. Set it in **Settings > Templates > Default template**.

### Custom templates

1. Open **Settings > Templates** (or **Manage Templates…** at the bottom of the template menu).
2. Click **New template**, or the duplicate button on any template to start from a copy.
3. Set the icon and **Name**, the **Instructions** (what Grok should focus on and how to write each section), the **Sections, in order** (each becomes a heading; empty sections are left out), and the **Topic focus** (what counts as a topic for this kind of meeting).
4. Click **Save**.

Built-in templates cannot be edited, only duplicated. Custom templates have edit (pencil) and delete buttons. When you delete a template, its meetings switch to the default template, and their notes stay until you regenerate them. Custom templates are saved in `templates.json`.

### Citations and clips

Facts and action items in enhanced notes end with transcript timestamps. Each timestamp shows as a small tinted pill:

- **▶ 5:17** when the meeting's audio is kept. Click it to play that clip, and click again to pause. Option-click it to open the transcript instead.
- **5:17** when the audio was not kept. Click it to open the **Transcript** tab at that moment, highlighted.
- Hover a pill to read the transcript line at that time. Right-click a pill for **Play from 5:17** and **Show in Transcript**.

Answers in the **Ask** tab, and action items and decisions on Home, have the same pills.

Clips need **Settings > Privacy & Data > Keep audio recordings after notes are written** to be on before the meeting. If it was off, a hint says "Turn on Keep audio in Settings to play clips from future meetings." Audio of past meetings cannot be recovered.

## Call summary

After the meeting, the call summary shows beside the notes, in a column on the right. It stays in view while you scroll the notes. When the window is narrow (for example with **Meeting info** open), it shows above the notes instead. Click **Call summary** to collapse or expand it there; Grok Notes remembers your choice.

The call summary shows:

- The duration, start time, and meeting app.
- **Speakers**: each speaker's talk time as a bar, a percent, and a duration. Hover for the word count. Click a name to rename it.
- **Chapters**: the meeting split into topic chapters, with start time and share of the meeting. Click a chapter to play from its start (or to show it in the transcript when the audio was not kept). While the meeting plays, the current chapter is highlighted.

Older meetings without chapters show their topics and a **Find chapters** button. It asks Grok to split the meeting into chapters ("Finding chapters…").

## Meeting player

When a meeting's audio is kept, a player bar appears at the bottom of the meeting:

- **Back 15 seconds**, **Play/Pause**, and **Forward 15 seconds** buttons.
- A timeline of the whole meeting. Chapters show as colored segments with titles above. Click or drag the line to scrub. Click a chapter title to play from its start. Hover to see the time and chapter.
- The speed menu: 1×, 1.25×, 1.5×, 2×.
- The voice levels panel (click the speaker icon):
  - **Balance voices** brings your mic and the other participants to the same speech level (on by default).
  - **My voice** and **Others** are separate sliders, from −12 dB to +12 dB. 0 dB is the balanced level (or the level as recorded, when **Balance voices** is off).
  - The speaker button next to each slider mutes that side.
  - **Reset** turns balancing on, sets both sliders to 0 dB, and unmutes both sides.
  - Changes apply while the meeting plays and are kept for the next meeting. A limiter keeps boosted voices from clipping.
  - The speaker icon turns blue when a level is changed from its default. It shows one wave when one side is muted, and a slash when both sides are muted.

Keyboard: Space plays or pauses. Left and right arrows move 5 seconds. These keys go to the focused control instead when it uses them: a text field you type in, a button, a slider, the tab switch, or the sidebar list (arrows only). With Full Keyboard Access on, Space presses the focused button.

In the **Transcript** tab, the block being played is highlighted. The **Follow** button keeps the transcript scrolled with playback. It stays faint until you point at it or move focus to it. Clips played outside the meeting (for example from Home) show a small bar with **Stop** (Escape).

## Transcript

The **Transcript** tab shows the conversation in blocks by speaker, each with a timestamp. Chapter titles appear between blocks. Each block has a faint play button (when audio is kept) that shows fully when you point at the block. Click a speaker chip to rename that speaker. Each speaker has a different color in a meeting, and you are always green. You can select and copy text.

### Find in the transcript

1. In the Transcript tab, press Command-F (or choose **Find in Transcript** in the **More** menu or the **Meeting** menu).
2. Type a word or name. Matches are highlighted, and the bar shows "3 of 12".
3. Press Return for the next match and Shift-Return for the previous one (or Command-G and Shift-Command-G, or the arrow buttons). The transcript scrolls to each match.
4. Press Escape or click **Done** to close the bar.

### Copy the transcript

To copy the transcript as plain text:

- **Copy Transcript** in the **More** menu copies the whole transcript. The first line is the meeting title and date. Each block is a line like `[04:12] Dana: text`, with resolved speaker names. When the meeting has chapters, each chapter starts with a heading like `## Pricing (04:12–10:30)`.
- The copy icon next to a chapter title copies only that chapter, with its heading.
- Right-click a block for **Copy** (that block) and, when there are chapters, **Copy from Here to End of Chapter**.
- The icon shows a checkmark for a moment after it copies.
- While you record, **Copy Transcript** copies the finished lines so far, without chapter headings. The live line is left out.

## Ask Grok

There are two chats:

- **Ask in a meeting** (the meeting's **Ask** tab). Questions about that one meeting, for example "What did we decide about pricing?" or "Draft a follow-up email." Answers cite timestamps.
- **Ask Grok in the sidebar** (Command-K, or **Meeting > Ask Grok**). One chat over every meeting, and help with Grok Notes itself.

### Across your meetings

Grok ranks your meetings by keywords, names, tags, and recency, picks up to 8 relevant ones (with an extra Grok request when you have more than 8 meetings), and answers from their notes and transcripts. Each answer links to its source meetings. Click a link to open the meeting. You can also type a question in the **Ask Grok about your meetings…** field on Home.

Click **New chat** (toolbar) to start over. The chat history is saved in `library-chat.json`.

### Help with Grok Notes

Ask how the app works in the same chat, for example "How do speaker names work?" or "Why is system audio off?". Questions that are clearly about the app are answered from this guide only, without reading your meetings, which costs less. Questions that could be about both get both. Answers about the app can include links that open **Settings**, **Usage & Cost**, **Home**, or a **System Settings** privacy pane.

Open this help any time with **Help > Grok Notes Help** (Command-?), or **Settings > General > Ask about Grok Notes**. **Open user guide** opens this guide as a file.

## Home

Home is the start page (click **Home** in the sidebar, or **Meeting > Home**, Shift-Command-H). It shows:

- A greeting, **Start notes**, and an **Ask Grok about your meetings…** field.
- **Up next**: today's remaining calendar events (up to 5, plus "+N more later today", and all-day events). Each has **Join** (when the event has a meeting link) and **Start notes**. If the calendar file is stale, Home says when it was last synced. **Calendar settings** opens Settings.
- **Open action items** from the last 30 days. Check an item to mark it done in that meeting's notes. **Show all** shows more.
- **Recent meetings**.
- **Trending topics** for **7 days** or **30 days**, and **Top tags**. Click one to list its meetings.
- **Recent decisions**, with links to their meetings.
- **This week**: **Meetings**, **In meetings** (time), and **Your talk time** (your share of everything said), each compared with last week. API spend is in **Usage & Cost**.

## Tags

Tags group meetings, for example by customer or project.

- **Add a tag**: open **Meeting info** (info button) > **Tags**. Type in **Add tag**, or pick one from the tag menu. Click × on a chip to remove it.
- From the sidebar: right-click a meeting > **Tags** to toggle tags or click **Suggest Tags**.
- **Suggest tags** asks Grok for tags for one meeting. It never removes a tag.

In **Settings > Tags**:

- **Tag meetings automatically when notes are written** (on by default).
- **Let Grok create new tags** (on by default). New tags Grok creates appear under **Suggested by Grok** until you click **Keep** or **Delete**. Grok prefers your own tags.
- Your tag catalog: set a color, rename, add **When it applies (optional)** to guide Grok, or delete a tag (it is removed from its meetings). Add tags with **New tag** and **Add**.
- **Tag existing meetings > Tag all untagged meetings** tags old meetings, one xAI request per meeting. It shows an estimated cost first, keeps existing tags, and you can cancel.

## Sidebar

- **Home** and **Ask Grok** at the top.
- **Tags**: the most used tags with counts. Click one to filter the list; click it again to clear. Other tags are under "N more tags".
- **Search meetings** (the search field) filters by title, notes, people, and transcript text. While filtering, a count and **Clear** appear.
- **Pinned** meetings, then date sections: **Today**, **Yesterday**, **Previous 7 Days**, **Previous 30 Days**, each month of this year, then older years. Click a section header to collapse it.
- Swipe right on a meeting to **Pin** or **Unpin**. Swipe left and click **Delete**. A full swipe does not delete.
- Right-click a meeting for **Pin**, **Tags**, **Copy as Markdown**, **Show in Finder**, and **Delete**.

### Delete and undo

Delete a meeting from the sidebar (swipe or right-click) or from **More > Delete Meeting** in the meeting.

1. The meeting moves to `~/Library/Application Support/GrokNotes/Trash/` with its notes, transcript, and audio.
2. A bar at the bottom says "Deleted “<title>”" for a few seconds. Click **Undo** to restore it.
3. Or press Command-Z (**Edit > Undo Delete Meeting**) while Grok Notes is open. Shift-Command-Z deletes it again.
4. Grok Notes removes meetings from the Trash folder 30 days after you delete them, when it opens. To restore one later, quit Grok Notes and move its folder from `Trash` back to `Meetings`.

You cannot delete a meeting while it is recording.

## Calendar

The calendar gives a meeting its title and invitees, helps name speakers, and fills **Up next** on Home. Pick the source in **Settings > Calendar & Drive > Source**:

| Source | Reads |
| --- | --- |
| **Automatic** (default) | `calendar.json` when it was synced in the last 24 hours, else Apple Calendar when allowed, else a stale `calendar.json` |
| **Google via Cursor** | `calendar.json` only |
| **Apple Calendar** | Apple Calendar (needs the Calendar permission) |
| **None** | Nothing |

The status line shows the active source, for example "Google via Cursor · synced 12 min ago · 14 events". Buttons: **Reveal file**, **Copy sync prompt**, and **Reload**.

### Google Calendar through Cursor

Grok Notes has no Google sign-in. A Cursor agent reads Google Calendar and writes `~/Library/Application Support/GrokNotes/calendar.json`. Grok Notes only reads that file.

1. Install the skill: `mkdir -p ~/.cursor/skills && cp -R skills/grok-notes-calendar-sync ~/.cursor/skills/` (from the Grok Notes source folder).
2. Connect a Google Calendar MCP server in **Cursor Settings > MCP**.
3. In Cursor, say **"Sync my calendar for Grok Notes"**. (**Settings > Calendar & Drive > Copy sync prompt** copies it.)
4. To keep it fresh while Cursor is open, run `/loop 30m sync my calendar for Grok Notes` in Cursor.

Grok Notes watches the file and reloads it within a minute. Events you declined are ignored.

### Apple Calendar

1. Set **Settings > Calendar & Drive > Source** to **Apple Calendar** (or **Automatic**).
2. In **Settings > Recording**, click **Allow** next to **Apple Calendar**.

## Google Drive export

With **Google Drive for desktop** installed and signed in, Grok Notes can copy each meeting into your synced My Drive. There is no Google sign-in in the app.

1. Open **Settings > Calendar & Drive**.
2. Turn on **Copy notes to Google Drive when saved**.
3. Optionally set **Subfolder under My Drive (optional)**, for example `Grok Notes`. Leave it blank to write at the top of My Drive.

On each save, the app copies `notes.md` and `meeting.json` to `My Drive/<subfolder>/<yyyy-MM-dd Meeting title>/`. Settings shows "Google Drive for desktop is mounted." or "Drive not found. Install Google Drive for desktop and sign in." If Drive is not mounted, the app keeps saving locally and does not show an error.

## Usage and cost

**Meeting > Usage & Cost** (Shift-Command-U), the menu bar menu (**Usage · $X mo.**), or **Settings > Privacy & Data > Usage & Cost** opens the **Usage & Cost** window. It shows your xAI spend for **Today**, **Last 7 days**, **This month**, or **All time**, **By feature** and **By meeting**. Each meeting's **Meeting info** shows its **API cost**.

- **Exact**: Grok requests (notes, names, topics, tags, answers, help questions) use the exact cost xAI returns.
- **Estimated**: transcription is estimated from recorded audio at list price: $0.20 per hour for live streaming, $0.10 per hour for the full-recording pass. Requests without a reported cost are estimated from tokens.

Help questions answered from this guide are listed as **Help questions**. The log is `~/Library/Application Support/GrokNotes/usage.jsonl`. Usage from before this page existed is not included.

## Privacy and data

Everything is stored on your Mac in `~/Library/Application Support/GrokNotes/` (**Settings > Privacy & Data > Show data folder** opens it):

- `Meetings/<id>/`: `meeting.json`, `notes.md`, and the audio (`mic.wav`, `system.wav`) if you keep it.
- `Trash/<id>/`: deleted meetings, kept 30 days so you can undo a delete.
- `library-chat.json` (Ask Grok history), `usage.jsonl`, `templates.json`, `tags.json`, and `calendar.json`.
- Your API key is in the Keychain. Settings are in the app's preferences.

What is sent to xAI (`api.x.ai`), and nowhere else:

- Your microphone and system audio, for live and full-recording transcription.
- Transcripts, rough notes, invitee names, and notes, to write notes, find names, topics, chapters, and tags, and to answer questions.
- Meeting-window snapshots, when snapshot naming is on. They are deleted after processing.

Audio settings in **Settings > Privacy & Data**:

- **Keep audio recordings after notes are written** (off by default). When off, the audio is deleted after the notes are written, and clips and the player are not available.
- **Delete kept audio after**: **Never**, **7 days**, **30 days**, or **90 days**. Old recordings are removed when Grok Notes opens. Notes and transcripts stay.

## Models and language

- Transcription always uses `grok-voice-transcribe-2.0`.
- Notes, names, tags, and answers use the model in **Settings > Models & API > Notes model** (default `grok-4.7`).
- Live answers use **Settings > Models & API > Live answers model** (default `grok-4.20-non-reasoning`, chosen for speed). Both model menus have **Custom…** to type any other model ID.
- **Settings > General > Meeting language** (default English, `en`) sets the transcription language. Pick **Custom…** to type another language code.
- Transcription gets your invitees and remembered people as key terms, so names are spelled right.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| Shift-Command-R | Start notes / Stop & write notes |
| Command-K | Ask Grok (all meetings and app help) |
| Shift-Command-H | Home |
| Shift-Command-U | Usage & Cost |
| Command-comma | Settings |
| Command-? | Grok Notes Help |
| Command-Return | Send in Ask Grok (sidebar chat) |
| Command-1 / 2 / 3 | Notes, Transcript, or Ask tab of the open meeting |
| Option-Command-I | Show or hide Meeting info |
| Shift-Command-C | Copy the meeting as Markdown |
| Option-Command-R | Regenerate notes |
| Command-F | Find in the transcript (Transcript tab) |
| Return / Shift-Return | Next or previous match (find bar) |
| Command-G / Shift-Command-G | Next or previous match (find bar) |
| Command-Z | Undo a delete |
| Option-click a ▶ timestamp | Open the transcript instead of playing |
| Space | Play or pause (meeting player) |
| Left / Right arrow | Back or forward 5 seconds (meeting player) |
| Escape | Stop a playing clip, or close the find bar |

## Troubleshooting

### "System audio is off" or remote voices are missing

The banner "System audio is off (…). Recording the microphone only." means macOS refused system audio. This happens when the permission is missing, when the app was not relaunched after granting it, or after a rebuild changed the app's signature (macOS then declines silently, even though the switch looks on).

1. Open **System Settings > Privacy & Security > Screen & System Audio Recording**.
2. Select **Grok Notes** and remove it with the minus button. Add it again with the plus button (or click **Allow** in **Settings > Recording**), and turn it on.
3. Quit and reopen Grok Notes.
4. If you build the app yourself, run `./scripts/create-signing-cert.sh` once so later rebuilds keep the permission.

### No audio from your mic, or no call audio

If the microphone meter stays flat or turns orange with "No audio from your mic":

1. Open **System Settings > Sound > Input** and check that the right device is selected and its input level moves when you talk.
2. Check that the microphone is not muted on the headset or in hardware.
3. If you changed devices during the call, stop and start notes again.

If the call-audio meter stays flat or shows "No call audio — is the meeting app playing through this Mac?":

1. Check that you can hear the other side on this Mac. Audio played on a phone or another device is not captured.
2. Check that **Screen & System Audio Recording** is on (see the next section).
3. Some apps play to a separate output device. Choose the same output in the meeting app and in **System Settings > Sound > Output**.

Both warnings are hints. A quiet listener or a long monologue can trigger them; the recording continues either way.

### Microphone error or echo cancellation message

- With system audio on, the app uses echo cancellation so remote voices from your speakers are not transcribed as you. Some devices (for example Bluetooth headsets, or input and output at different sample rates) refuse it with error -10875. Then the app falls back to the plain microphone and shows "Echo cancellation is not supported by your current audio devices. Use headphones so other voices are not transcribed as you."
- If you always wear headphones, turn off **Settings > Recording > Echo cancellation**.
- "Could not start the microphone" means no input device is available or another app holds it. Check **System Settings > Sound > Input**, then start again.
- "Grok Notes needs microphone access" means the Microphone permission is off. Turn it on in **System Settings > Privacy & Security > Microphone**.

### My voice is quiet

The app automatically raises a quiet microphone by up to 12 dB while recording. In playback, keep **Balance voices** on in the player's voice levels panel, or raise **My voice** (or lower **Others**).

### Names are not detected (everyone is "Them")

- Check **Accessibility** and **Screen & System Audio Recording** in **Settings > Recording**. Active-speaker names and snapshots need system audio.
- Start notes while the call is open, so the meeting app is detected (the button reads **Start notes · <App>**).
- Make sure **Identify speakers from meeting-window snapshots** and **Let Grok infer names from the conversation** are on.
- A calendar event with invitees helps a lot, especially in one-on-ones.
- Rename speakers yourself. Your names are remembered for later meetings. Then choose **Regenerate Notes** (Option-Command-R) to rewrite the notes with the names.

### Calendar is stale or empty

- Check the status line in **Settings > Calendar & Drive**. "Stale: last synced …" means `calendar.json` is older than 24 hours. Say "Sync my calendar for Grok Notes" in Cursor, or run `/loop 30m sync my calendar for Grok Notes`, then click **Reload**.
- "calendar.json could not be read" means the file is malformed. Sync again.
- For Apple Calendar, allow the Calendar permission and set the source to **Apple Calendar** or **Automatic**.

### Google Drive copies are missing

Settings says "Drive not found" when Google Drive for desktop is not installed, not signed in, or not mounted under `~/Library/CloudStorage`. Open Google Drive for desktop and sign in. The app keeps saving locally. Copies are made on the next save of each meeting.

### Other messages

- "Add your xAI API key in Settings" means no key is saved. See [Getting started](#getting-started).
- "Transcribing full recording failed: Kept the live transcript." The notes still use the live transcript.
- "Writing notes failed" in the Notes tab means a request failed. Click **Retry** (or **Write notes**, or **Regenerate Notes** in the **More** menu) to try again.
- "Tagging failed" or "Naming speakers failed": click **Retry** next to the message.
- "The audio for this meeting is no longer on this Mac." means the audio was not kept or was deleted by the retention setting.
