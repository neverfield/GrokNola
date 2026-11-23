# GrokNola user guide

GrokNola is a meeting notepad for macOS. No bot joins your call. The app listens to your microphone and to your Mac's audio, transcribes live with `grok-voice-transcribe-2.0`, and writes notes with `grok-4.7`. Everything runs on the xAI API with your own API key.

## Getting started

1. Open **Settings** (Command-comma, or **Settings** in the menu bar menu).
2. In the **Models & API** pane, under **xAI API**, paste your key into **API key** and click **Save key**. The key is stored in the macOS Keychain. Click **Test connection** to check it. ("Connected. N models available." means it works.) The Keychain is the only place GrokNola reads the key from.
3. In the **General** pane, under **You**, check **Your name**. It defaults to your macOS account name. The app uses it for your speaker label and never gives your name to another speaker.
4. In the **Recording** pane, under **Permissions**, click **Allow** next to each permission you want (see [Permissions](#permissions)). After you grant **Screen & System Audio Recording**, click **Relaunch GrokNola**.
5. Click **Refresh status** to update the check marks.

Home also shows a setup checklist (xAI API key, Microphone, Screen & System Audio Recording, Accessibility, Calendar) with an **Open Settings** link until you have recorded a meeting.

## Permissions

GrokNola asks for four macOS permissions. Only the microphone is required.

| Permission | Why it matters | Without it |
| --- | --- | --- |
| **Microphone** | Records your voice. | You cannot start notes. |
| **Screen & System Audio Recording** | Records the other participants from the meeting app's audio, on a separate stream from your mic. Also lets the app read meeting window titles (meeting detection) and, when you turn it on, take call-window snapshots for speaker names. | Microphone only. Everyone is mixed together, and remote speakers are harder to separate. |
| **Accessibility** | Optional. When you turn on **Settings > Speakers > Read who is talking from the meeting app**, reads the call window's "who is talking" indicator, so remote speakers get real names. | Names come from the transcript, snapshots if on, and your corrections. Often Me / Them. |
| **Apple Calendar** | Meeting title and invitees from Apple Calendar, when Apple Calendar is the calendar source. | Connect Google Calendar instead, or use no calendar. |

To grant a permission:

1. Open **Settings > Recording** and click **Allow**. macOS shows a prompt, or opens **System Settings > Privacy & Security**.
2. In System Settings, turn on **GrokNola** in the matching list (**Microphone**, **Screen & System Audio Recording**, **Accessibility**, or **Calendars**).
3. For Screen & System Audio Recording, click **Relaunch GrokNola** (or quit and reopen the app). macOS applies it only on relaunch.

### Keep permissions across rebuilds

macOS ties privacy permissions to the app's code signature. If you build the app yourself, run `./scripts/create-signing-cert.sh` once. It creates a local certificate named "Grok Notes Local Signing" in a separate, locked keychain with its own password, and `./scripts/build-app.sh` signs every build with it (asking for that password), so rebuilds keep their permissions. Set `CODESIGN_IDENTITY` to use another certificate. Without a certificate, the build is signed ad hoc, the signature changes on every build, and macOS forgets the permissions.

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

When GrokNola finds the meeting app in a call (Zoom, Teams, Slack, Webex, FaceTime, or a Google Meet tab), it records system audio from that app only. Other apps, such as music or a video in another browser, are not recorded. When no meeting app is found, it records all of your Mac's audio except GrokNola's own.

### Before recording starts

Every way to start (the sidebar, Home, **Up next**, the menu bar, **Meeting > Start Notes**, and the "call detected" notification) runs the same checks, in this order:

1. **Blocked domains.** If the invite lists anyone at a domain in **Settings > Privacy & Data > Never record meetings with** (including subdomains, such as `eng.example.org` for `example.org`, plus any domains your build always blocks), recording does not start and a message says "GrokNola doesn't record meetings with people at blocked domains." This applies whatever the other settings are.
2. **Which meetings to record** (**Settings > Privacy & Data > Record**):
   - **Internal meetings only** (the strictest setting): recording does not start when the invite lists anyone outside your company domains. Without an invite, or with no invitees, you must confirm consent first.
   - **Any meeting, confirm when outside people are invited** (the default): outside invitees always bring up the consent confirmation, even when it is turned off.
   - **Any meeting**: only the consent settings below apply.
3. **FileVault.** If FileVault is off, or GrokNola can't confirm it is on, a warning appears with **Open FileVault Settings**. A pilot build does not record until FileVault is on.
4. **Consent confirmation.** A dialog says "Everyone in this meeting knows you're taking AI notes and agreed where the law requires it." When the invite lists outside people, it names their domains. Click **Start Notes** to record, or **Cancel**. The time you confirmed and the outside domains are saved with the meeting.

The confirmation is on by default (**Settings > Privacy & Data > Confirm consent before every recording**). For a meeting whose invitees are all in your company domains, the dialog offers **Don't ask again for internal-only meetings**; turn that back off with **Don't ask for internal-only meetings** in the same place. A meeting with outside invitees, or without an invite, always asks.

### Consent reminder

When the calendar invite lists people outside your company and you did not just confirm consent, a warning says: "This meeting includes people outside your company. Tell everyone you're taking AI notes, and get their consent where the law requires it." It stays until you close it.

- Your company's domains come from **Settings > Privacy & Data > Company email domains** (for example `example.com`), your own address on the invite, and your Google Calendar sign-in. Subdomains count as yours. Calendar rooms do not count as people.
- If GrokNola can't tell which domain is yours, it reminds you whenever the invite lists anyone.
- Turn it off in **Settings > Privacy & Data > Remind me to ask for consent when outside people are invited**. The reminder does not replace your company's recording policy.

### Meeting detection

Every few seconds, the app checks for a call in Zoom, Microsoft Teams, Slack (huddles), Webex, FaceTime, or Google Meet in a browser (Chrome, Safari, Arc, Edge, Brave, Firefox, Vivaldi). When it finds one, the menu bar icon changes and the menu offers **Start Notes · <App>**. Detection never starts recording by itself.

The first time a call is detected, macOS asks whether GrokNola may send notifications. If you allow it, a notification "<App> call detected — Start notes for this call?" appears once per call; click **Start Notes** on it to begin. If you deny it, nothing else changes. To turn this notification off, run `defaults write com.neverfield.groknola notifyOnMeetingDetected -bool false` and relaunch.

- Google Meet is found from the browser tab title, which needs **Screen & System Audio Recording**.
- With that permission, Zoom and Slack count only when a call window is open ("Zoom Meeting", "Huddle"). Otherwise an app counts while another app is using the microphone.

### While recording

- Type rough notes in the notes editor ("Jot rough notes here while you talk…"). Short phrases are fine. They become the backbone of the enhanced notes.
- Under the notepad, a **Live** strip shows the last thing heard from the other side and from **You**. The other side is labeled with the speaker's name once it is known, else **Them**. Click **Live** to collapse or expand it; the app remembers your choice.
- The **Transcript** tab shows the live transcript. A **Live** box shows the words being heard now, labeled with the speaker's name (or **Them**) and **Me**. If you scroll up, click **Jump to latest** to follow again.
- Speakers are named as people talk (see [Names during the call](#names-during-the-call)). Click any name, in the transcript or the Live strip, to correct it.
- A bar at the bottom of the window shows the elapsed time, a level meter for your microphone and one for call audio, and **Stop & Write Notes**. The bars move when sound arrives, so you can see that both sides are being captured.
- The meter bars are amber. A meter turns red when that side looks silent: your mic has had no signal for 20 seconds while others talk, or there has been no call audio for 20 seconds while you talk. Hover over it for the reason. See [No audio from your mic, or no call audio](#no-audio-from-your-mic-or-no-call-audio).
- If the transcription connection drops, an ochre "Transcription reconnecting" message appears next to the meters. The app reconnects by itself.
- The menu bar menu shows the meeting title, the elapsed time, **Open Notes**, **Pause Recording**, and **Stop & Write Notes**.

### Pause

Click **Pause** in the bottom bar, use **Meeting > Pause Recording** (Option-Command-P), or the menu bar menu > **Pause Recording**. While paused:

- Nothing is recorded or transcribed. The saved audio has silence for that stretch, so playback and transcript times still match the meeting's clock. Paused time is not charged for live transcription.
- The clock keeps running and shows **Paused**. The sidebar, Home, and the menu bar show a pause mark instead of the red dot.
- Window snapshots, and reading who is talking from the meeting app, stop. GrokNola does not ask whether you forgot to stop until the pause is longer than 30 minutes; then it asks "Still recording?" (see [If you forget to stop](#if-you-forget-to-stop)).

Click **Resume** (Option-Command-P again) to carry on. Live speaker names may start over after a pause, as after a reconnect; the pass after the meeting names the speakers for the whole recording.

### Stop

Click **Stop & Write Notes** in the bottom bar, use **Meeting > Stop & Write Notes** (Shift-Command-R), or the menu bar menu > **Stop & Write Notes**. Then the app:

1. Re-transcribes the full recording with diarization, so speaker numbers are stable for the whole meeting. If this pass fails, the live transcript is kept.
2. Names the speakers (see [Speaker names](#speaker-names)).
3. Writes enhanced notes with the meeting's summary template.
4. Finds topics and chapters.
5. Adds tags, when automatic tagging is on.

The Notes tab shows these steps as they run: **Transcribing full recording**, **Naming speakers**, **Writing notes**, and **Tagging**. Each step shows a check mark when done, a spinner while it runs, an empty circle while it waits, or an ochre mark when it failed. While Grok writes, the notes area shows the headings of the meeting's template with placeholder lines. Switch to **My notes** to see your rough notes. The sidebar row shows a spinner.

If a step fails, the reason appears under the steps. Click **Retry** to run only that step again (writing notes, naming speakers, or tagging). The full-recording pass cannot be retried; the live transcript is kept. Click the close button to hide the steps.

If you stop without any transcript or notes, a message says "Nothing was recorded, so the meeting was discarded."

### If you forget to stop

GrokNola asks "Still recording?" when the call seems to be over:

- The call window closed, or the meeting app quit. This works for Zoom meetings, Slack huddles, and Google Meet tabs, and needs the Screen & System Audio Recording permission. For Teams, Webex, and FaceTime it notices only when the app quits.
- Nobody spoke on either side for 5 minutes.
- The calendar meeting ended more than 2 minutes ago and nobody spoke for 2 minutes.
- The recording has been paused for more than 30 minutes.

A recording stops by itself after 8 hours and writes the notes.

The question shows as a message at the top of the window and as a notification. Choose **Keep Recording**, or close the message, to carry on; it will not ask again for 10 minutes. Choose **Stop Now** in the notification to stop. If you do not answer, GrokNola stops and writes the notes 2 minutes later. When someone speaks again, or the call window comes back, the question goes away by itself.

Turn this off, or change how long a silence counts, in **Settings > Recording > Forgotten recordings**.

### Notifications

When processing finishes and you are not looking at that meeting, a notification says "Notes ready". Click it to open the meeting. If writing the notes failed, the notification says "Grok could not write the notes" instead, and the meeting keeps its step list with **Retry**. Notifications can show on the lock screen, so they never include the meeting title or any notes. Notifications need permission, which macOS asks for the first time one is sent. Change it later in **System Settings > Notifications > GrokNola**.

### Messages

Messages appear across the top of the window. Slate-blue messages are information and close by themselves. Ochre messages are warnings, and red messages are errors; they stay until you close them. Some have a button, such as **Open Settings** when the API key is missing. At most two show at once; "N more messages" and **Dismiss All** appear when there are more.

## Speaker names

Your microphone and your Mac's audio are recorded on separate streams. Your mic is **you**. The system audio is diarized (split by voice) into remote speakers. Then the app puts names on remote speakers from this evidence, strongest first:

1. **Your corrections.** A name you set is never overwritten.
2. **Active speaker** (off by default; needs Accessibility and system audio). Turn it on in **Settings > Speakers > Read who is talking from the meeting app**. While you record, the app reads the meeting app's accessibility labels once a second, such as "Talking: Ana" or "Ana is speaking". For Zoom, Slack, and Google Meet it reads only the call window ("Zoom Meeting", "Huddle", "Meet - …"); for other apps it reads at most 3 windows. Reading stops while the recording is paused, and the accessibility settings GrokNola turned on in the meeting app are put back when you stop. A voice gets a name when that name was shown in at least 3 samples and in 60% or more of the samples during that voice's speech. Label: "active speaker".
3. **Window snapshots** (off by default; needs Screen & System Audio Recording). Turn it on in **Settings > Speakers > Identify speakers from meeting-window snapshots**. While remote participants talk, the app saves an encrypted snapshot of the call window every 4 seconds. Only a window whose title shows the call is captured: "Zoom Meeting", "Zoom Webinar", a Slack "Huddle", or a Google Meet tab. The title is checked before every snapshot, and Teams, Webex, and FaceTime windows are never captured. Snapshots can show faces, chat, and shared screens. After the meeting, Grok vision reads the highlighted tile and participant names. It accepts a name at 70% confidence or more. The snapshots are sent to xAI and deleted after processing. Label: "seen on screen".
4. **One-on-one rule.** When there is exactly one remote voice and exactly one other invitee (or one other participant visible in the call window), that voice gets that name.
5. **Transcript inference.** Grok reads the transcript for introductions ("This is Dana from finance") and people addressed by name, matched against calendar invitees and names seen in the meeting app. People from past meetings are not sent to Grok; a name Grok returns is matched to them on your Mac. It needs 75% confidence for a known name and 85% for any other name. Label: "inferred by Grok". Turn this off in **Settings > Speakers > Let Grok infer names from the conversation**.

A remote speaker without strong evidence stays **Them**. When permissions are missing or the app is not supported, you fall back to Me / Them. Without system audio, the microphone alone is diarized and the voice that talks most is labeled as you.

### Names during the call

With **Settings > Speakers > Identify speakers live** on (the default) and system audio available, names appear while you record instead of only after you stop:

- **Active speaker.** Each second the meeting app shows one person talking counts as a vote for the voice heard at that moment.
- **Introductions.** "This is Dana", "I'm Dana", or "Dana here" counts when Dana is an invitee, a person from past meetings, or a name shown in the meeting app. "My name is …" counts for any name.
- **One-on-one calls.** With one other invitee and one remote voice, that voice is named at once. The name is taken back if a second voice or another name shows up.
- **Snapshots.** If a voice is still unnamed after about 30 seconds, Grok reads the call-window snapshots for it, at most once a minute and 8 times a meeting. These requests appear in **Usage & Cost** as "Speaker names (snapshots)". This is off by default; turn it on in **Settings > Speakers > Send snapshots for unnamed speakers during the call** (needs snapshots on).

A name first shows dimmed with a **?**, such as "Dana?", while it is a guess. It is confirmed when the evidence adds up, for example 4 active-speaker samples with 70% or more agreeing, and the **?** goes away. A voice with no name yet shows "identifying…". Confirmed names are saved with the meeting; guesses are not. Click a name to confirm it or set another. If you clear a name, the same guess does not come back for that voice.

After you stop, the full-recording pass splits voices again. Names found during the call, and names you set, carry over to the matching voices, and the steps in [Speaker names](#speaker-names) fill in the rest. A live name is replaced only by clearly stronger evidence for someone else. **Meeting info > Speakers** marks these names "found live".

### Rename a speaker

1. Click a speaker name: in the transcript, in the call summary, or in **Meeting info** (the info button in the toolbar) > **Speakers**.
2. In "Who is this?", type a name or click a suggestion (invitees and remembered people).
3. Click **Save**. **Clear name** goes back to Me or Them.

If you type a name another speaker in the meeting already has, GrokNola asks whether to merge the two speakers. **Keep separate** saves the name on both.

### Merge speakers and move lines

Sometimes one person shows up as several speakers, for example two or three **Them**s. Speakers that share a name show a number and when they first talk, such as "Them 2 · 03:12".

- **Merge two speakers.** Click a speaker name and choose **Merge with…**, or Control-click a speaker block in the transcript, or a speaker row in the call summary, and choose **Merge into**. All lines of the first speaker go to the second. The second speaker keeps its name, or takes the first speaker's name when it has none. Your own lines always stay yours.
- **Move one block.** Control-click a block in the transcript and choose **This line is** and the right speaker.

While recording, later lines from a merged voice join the speaker you merged it into. Edit > Undo (Command-Z) takes back a merge or a move. When the meeting already has enhanced notes, a banner offers **Regenerate notes**, and **Regenerate for new speakers** shows above the notes until you do.

Names you set, and names confirmed by the active speaker or snapshots, are remembered on your Mac. They help match names in later meetings and appear as suggestions, but they are not sent to xAI. **Settings > Speakers** shows the count under **Remembered people**.

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
- To fix a name or a line, click **Edit** at the top right of the notes (or **Edit Notes** in the **More** menu). The notes show as Markdown with light styling. Type your changes. They save by themselves. Click **Done** to see the formatted notes again. Editing is off while Grok writes notes. Checking a box also counts as an edit.

### Regenerate and your edits

**Regenerate Notes**, **Regenerate with <template>**, and **Retry** on a failed **Writing notes** step write new enhanced notes. If you edited the enhanced notes since Grok wrote them, the app asks "Regenerate notes?" first:

- **Regenerate** replaces your edits.
- **Save edits to My notes, then regenerate** adds your edited notes to the end of your rough notes, under `## Previous edited notes (<date>)`, and then regenerates. Grok treats that section as your corrections, so fixes like names carry over.
- **Keep my edits** cancels.

The notes written when you click **Stop & Write Notes** never ask, because there are no edits yet.

After a regenerate replaces notes, a message offers **Undo regenerate**. **Edit > Undo Regenerate Notes** (Command-Z) does the same. Undo brings back the previous notes, and your rough notes as they were if you saved edits to them and did not change them since. Undo works for the last regenerate of each meeting until you quit. The **Undo regenerate** button does nothing once you change the new notes.

### The More menu and Share

The **More** button (**…**) in the meeting toolbar has:

- **Regenerate Notes** (Option-Command-R) writes the enhanced notes again, for example after you add rough notes or rename speakers. It asks first when you edited the notes (see [Regenerate and your edits](#regenerate-and-your-edits)). It reads **Write Notes** when a meeting has no enhanced notes yet. **Regenerate with <template>** appears when you picked another template.
- **Edit Notes**.
- **Copy Markdown** (Shift-Command-C) copies the whole meeting (title, attendees, call summary, notes, transcript) as Markdown.
- **Copy Transcript** copies the transcript as plain text (see [Transcript](#transcript)).
- **Find in Transcript** (Command-F in the Transcript tab).
- **Export Transcript and Audio…** asks for a folder and saves readable copies there: `notes.md` with the transcript, `meeting.json`, and the recordings if you keep them. It is not available while recording or writing notes.
- **Show in Finder** opens the meeting's folder. The files there are encrypted, so use **Export Transcript and Audio…** for copies you can open.
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

Built-in templates cannot be edited, only duplicated. Custom templates have edit (pencil) and delete buttons. When you delete a template, its meetings switch to the default template, and their notes stay until you regenerate them. Custom templates are saved encrypted in `templates.json.enc`.

### Citations and clips

Facts and action items in enhanced notes end with transcript timestamps. Each timestamp shows as a small amber pill:

- **▶ 5:17** when the meeting's audio is kept. Click it to play that clip, and click again to pause. Option-click it to open the transcript instead.
- **5:17** when the audio was not kept. Click it to open the **Transcript** tab at that moment, highlighted.
- Hover a pill to read the transcript line at that time. Right-click a pill for **Play from 5:17** and **Show in Transcript**.

Answers in the **Ask** tab, and action items and decisions on Home, have the same pills.

Other links in notes and answers are written by Grok, so GrokNola treats them with care. Only web (`https`) and email links open, and only after you click **Open**. The question names the site, or the email's recipient, and the full address shows in a box you can scroll and select. When the address is long enough to carry meeting text (over 200 characters, or a query over 100), it also says "This link carries a lot of data in its address." Email links open without their message body and Cc or Bcc recipients, so a link cannot send your notes to someone else. Other kinds of links show as plain text and do nothing.

Grok is told that transcripts, notes, titles, and names are meeting data, not instructions, and to add no links except GrokNola's own. Check links anyway: someone on a call can still say a web address.

Clips need **Settings > Privacy & Data > Keep audio recordings after notes are written** to be on before the meeting. If it was off, a hint says "Turn on Keep audio in Settings to play clips from future meetings." Audio of past meetings cannot be recovered.

## Call summary

After the meeting, the call summary shows beside the notes, in a column on the right. It stays in view while you scroll the notes. When the window is narrow (for example with **Meeting info** open), it shows above the notes instead. Click **Call summary** to collapse or expand it there; GrokNola remembers your choice.

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
  - The speaker icon turns amber when a level is changed from its default. It shows one wave when one side is muted, and a slash when both sides are muted.

Keyboard: Space plays or pauses. Left and right arrows move 5 seconds. These keys go to the focused control instead when it uses them: a text field you type in, a button, a slider, the tab switch, or the sidebar list (arrows only). With Full Keyboard Access on, Space presses the focused button.

In the **Transcript** tab, the block being played is highlighted. The **Follow** button keeps the transcript scrolled with playback. It stays faint until you point at it or move focus to it. Clips played outside the meeting (for example from Home) show a small bar with **Stop** (Escape).

## Transcript

The **Transcript** tab shows the conversation in blocks by speaker, each with a timestamp. Chapter titles appear between blocks. Each block has a faint play button (when audio is kept) that shows fully when you point at the block. Click a speaker's name to rename that speaker. Each speaker has a different color in a meeting, and you are always sage green. You can select and copy text.

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
- **Ask Grok in the sidebar** (Command-K, or **Meeting > Ask Grok**). One chat over every meeting, and help with GrokNola itself.

### Across your meetings

Grok ranks your meetings by keywords, names, tags, and recency, picks up to 8 relevant ones (with an extra Grok request when you have more than 8 meetings), and answers from their notes and transcripts. Each answer links to its source meetings. Click a link to open the meeting. You can also type a question in the **Ask Grok about your meetings…** field on Home.

Click **New chat** (toolbar) to start over. The chat history is saved in `library-chat.json`.

### Help with GrokNola

Ask how the app works in the same chat, for example "How do speaker names work?" or "Why is system audio off?". Questions that are clearly about the app are answered from this guide only, without reading your meetings, which costs less. Questions that could be about both get both. Answers about the app can include links that open **Settings**, **Usage & Cost**, **Home**, or a **System Settings** privacy pane.

Open this help any time with **Help > GrokNola Help** (Command-?), or **Settings > General > Ask about GrokNola**. **Open user guide** opens this guide as a file.

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

- The GrokNola name, then **Home** and **Ask Grok** at the top.
- Each meeting row shows the date and app, and a colored dot for each of its first three tags.
- **Tags**: the most used tags with counts. Click one to filter the list; click it again to clear. Other tags are under "N more tags".
- **Search meetings** (the search field) filters by title, notes, people, and transcript text. While filtering, a count and **Clear** appear.
- **Pinned** meetings, then date sections: **Today**, **Yesterday**, **Previous 7 Days**, **Previous 30 Days**, each month of this year, then older years. Click a section header to collapse it.
- Swipe right on a meeting to **Pin** or **Unpin**. Swipe left and click **Delete**. A full swipe does not delete.
- Right-click a meeting for **Pin**, **Tags**, **Copy as Markdown**, **Export Transcript and Audio…**, **Show in Finder**, and **Delete**.

### Delete and undo

Delete a meeting from the sidebar (swipe or right-click) or from **More > Delete Meeting** in the meeting.

1. The meeting moves to `~/Library/Application Support/GrokNotes/Trash/` with its notes, transcript, and audio.
2. A bar at the bottom says "Deleted “<title>”" for a few seconds. Click **Undo** to restore it.
3. Or press Command-Z (**Edit > Undo Delete Meeting**) while GrokNola is open. Shift-Command-Z deletes it again.
4. GrokNola removes meetings from the Trash folder 30 days after you delete them, when it opens. To restore one later, quit GrokNola and move its folder from `Trash` back to `Meetings`.

You cannot delete a meeting while it is recording. Under legal hold (see [Retention, legal hold, and export for Legal](#retention-legal-hold-and-export-for-legal)), Delete still moves the meeting to the trash, a message says it is kept until the hold is lifted, and the trash is not emptied.

## Calendar

The calendar gives a meeting its title and invitees, helps name speakers, and fills **Up next** on Home. Pick the source in **Settings > Calendar & Drive > Source**:

| Source | Reads |
| --- | --- |
| **Automatic** (default) | Google Calendar when connected, else Apple Calendar when allowed |
| **Google Calendar** | Your primary Google Calendar |
| **Apple Calendar** | Apple Calendar (needs the Calendar permission) |
| **None** | Nothing |

The status line shows the active source, for example "Google · you@example.com · updated 2 min ago · 9 events".

### Google Calendar

1. Open **Settings > Calendar & Drive** and click **Connect Google Calendar**.
2. Your browser opens Google's sign-in page. Choose your work account and allow GrokNola to see your calendar events.
3. When the browser says you can close the tab, go back to GrokNola. The status line shows your account and the number of events.

GrokNola asks only to read events. It keeps the sign-in in your Keychain and the events in memory, refreshes them every 5 minutes and when the Mac wakes, and talks to Google directly from your Mac. Events you declined are ignored. Click **Reload** to refresh now, or **Disconnect Google** to sign out; that also revokes GrokNola's access at Google.

If Settings says "Google sign-in is not configured in this build", the app was built without an OAuth client. Whoever builds GrokNola adds one; see the README.

### Apple Calendar

1. Set **Settings > Calendar & Drive > Source** to **Apple Calendar** (or **Automatic**).
2. In **Settings > Recording**, click **Allow** next to **Apple Calendar**.

## Google Drive export

With **Google Drive for desktop** installed and signed in, GrokNola can copy each meeting into your synced My Drive. There is no Google sign-in in the app. A pilot build, or the `allowDriveExport` policy switch set to false, turns this off: the toggle is disabled and nothing is copied.

1. Open **Settings > Calendar & Drive**.
2. Turn on **Copy notes to Google Drive when saved**.
3. Pick the **Drive account**. **Match my Google sign-in** uses the Drive account with the same email as your Google Calendar sign-in, or else the only one in your **Company email domains** (**Settings > Privacy & Data**). With no match, nothing is copied until you pick an account. An account you pick is never swapped for another, even when it is not mounted.
4. Optionally set **Subfolder under My Drive (optional)**, for example `GrokNola`. Leave it blank to write at the top of My Drive. A name made only of dots is refused, and a leading dot becomes `_`.

After recording stops, each save writes `notes.md` to `My Drive/<subfolder>/<yyyy-MM-dd Meeting title>/`. Nothing is copied while the meeting records. It holds the notes and call summary only. The transcript and recordings are never copied to Drive automatically; use **Export Transcript and Audio…** to save them yourself. Settings shows where notes go, such as "Notes go to ana@example.com.", or what is missing. If Drive is not mounted, the app keeps saving locally and does not show an error.

## Usage and cost

**Meeting > Usage & Cost** (Shift-Command-U), the menu bar menu (**Usage · $X mo.**), or **Settings > Privacy & Data > Usage & Cost** opens the **Usage & Cost** window. It shows your xAI spend for **Today**, **Last 7 days**, **This month**, or **All time**, **By feature** and **By meeting**. Each meeting's **Meeting info** shows its **API cost**.

- **Exact**: Grok requests (notes, names, topics, tags, answers, help questions) use the exact cost xAI returns.
- **Estimated**: transcription is estimated from recorded audio at list price: $0.20 per hour for live streaming, $0.10 per hour for the full-recording pass. Requests without a reported cost are estimated from tokens.

Help questions answered from this guide are listed as **Help questions**. The log is `~/Library/Application Support/GrokNotes/usage.jsonl`. It names meetings only by ID; the window looks up each title, and a deleted meeting shows as "Deleted meeting". Usage from before this page existed is not included.

## Privacy and data

Everything is stored on your Mac in `~/Library/Application Support/GrokNotes/` (**Settings > Privacy & Data > Show data folder** opens it):

- `Meetings/<id>/`: `meeting.json.enc` (the notes and transcript), the audio (`mic.wav.enc`, `system.wav.enc`) if you keep it, and `frames/` (window snapshots used to name speakers). All of them are encrypted.
- `Trash/<id>/`: deleted meetings, kept 30 days so you can undo a delete.
- `library-chat.json.enc` (Ask Grok history), `known-people.json.enc` (remembered people), `templates.json.enc`, and `tags.json.enc`, all encrypted, and `usage.jsonl` (costs by meeting ID, without titles).
- Your API key and Google sign-in are in the Keychain. Calendar events are kept in memory only. Settings are in the app's preferences.

Meeting files are encrypted with AES-GCM. The key is kept in your login Keychain as `vault_key` under `dev.local.groknotes`, readable only on this Mac. Other apps see only encrypted bytes, and macOS asks you before any other app can read the key. While a meeting records and until its notes are written, the audio is not yet encrypted. Meetings from before encryption are encrypted the next time GrokNola opens.

If the `vault_key` Keychain item is deleted, encrypted meetings cannot be opened again. Use **Export Transcript and Audio…** to keep readable copies of meetings you need.

What is sent to xAI (`api.x.ai`), and nowhere else. (Google Calendar sign-in talks only to Google, and only to read your events.)

- Your microphone and the meeting app's audio, for live and full-recording transcription. This meeting's invitee names and your name go with it as key terms.
- Transcripts, rough notes, invitee names, and notes, to write notes, find names, topics, chapters, and tags, and to answer questions.
- Call-window snapshots, only when snapshot naming is on (off by default). They are deleted after processing.

GrokNola talks to xAI and Google over TLS 1.2 or later, and keeps no web cache or cookies for those connections. Your API key is read only from the Keychain.

Audio settings in **Settings > Privacy & Data**:

- **Keep audio recordings after notes are written** (off by default). When off, the audio is deleted after the notes are written, and clips and the player are not available. Under legal hold the audio is kept and encrypted anyway.
- **Delete kept audio after**: **Never**, **7 days**, **30 days**, or **90 days**. Old recordings are removed when GrokNola opens. Notes and transcripts stay. Not available under legal hold.

### Retention, legal hold, and export for Legal

In **Settings > Privacy & Data > Retention and legal hold**:

- **Delete meetings after**: **Never** (the default), **30 days**, **90 days**, **180 days**, or **365 days**. When GrokNola opens, meetings that started longer ago are deleted for good, with their transcript, notes, and audio. Pinned meetings are deleted too.
- **Legal hold** (off by default). Turn it on when Legal asks you to preserve meetings. While it is on, nothing is deleted: the audio of meetings whose notes are written during the hold is kept even with **Keep audio** off, meeting and audio retention are suspended, the trash is not emptied, Delete only moves a meeting to the trash, and **Forget person** is unavailable. Audio deleted before the hold was turned on cannot be recovered.
- **Export all for Legal…** asks for a folder, then writes `GrokNola Legal Export <date>` there. Each meeting, including those in the trash, gets a folder with `notes.md`, `transcript.txt`, `meeting.json`, and any kept audio. `manifest.json` lists each meeting's ID, title, start time, whether it was in the trash, and each file's name, size, and SHA-256 hash. The copies are not encrypted. Wait until nothing is recording or being processed.

### Forget a person

**Settings > Speakers > Forget person…** asks for a name, then removes it from your remembered people and from the speakers of every meeting, including the trash, ignoring capitals. Those voices show as unidentified. Transcript text, notes, and invitee lists are not changed. It is not available while a meeting records or its notes are being written, or under legal hold.

### Pilot builds

A pilot build is made with `GROKNOLA_PILOT=1 ./scripts/build-app.sh`. It turns off the Google Drive copy, records internal meetings only, keeps snapshots and **Read who is talking from the meeting app** off, always asks for the consent confirmation, and does not record unless FileVault is on. In Settings these switches are disabled and say "Set by the pilot build."

Any build can also block domains for good with `GROKNOLA_BLOCKED_DOMAINS="example.org example.net" ./scripts/build-app.sh`. Settings lists them under **Never record meetings with**, and they apply on top of the domains you type there.

## Models and language

- Transcription always uses `grok-voice-transcribe-2.0`.
- Notes, names, tags, and answers use the model in **Settings > Models & API > Notes model** (default `grok-4.7`).
- The model menu lists the only models GrokNola uses: `grok-4.7`, `grok-4.6`, `grok-4.3`, and `grok-4.20-non-reasoning`. A model ID typed in an older version is replaced by the default.
- **Settings > General > Meeting language** (default English, `en`) sets the transcription language. Pick **Custom…** to type another language code.
- Transcription gets this meeting's invitees and your name as key terms (at most 40), so names are spelled right. Remembered people from past meetings are not sent; they are only matched on your Mac.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| Shift-Command-R | Start notes / Stop & write notes |
| Option-Command-P | Pause / resume recording |
| Command-K | Ask Grok (all meetings and app help) |
| Shift-Command-H | Home |
| Shift-Command-U | Usage & Cost |
| Command-comma | Settings |
| Command-? | GrokNola Help |
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
2. Select **GrokNola** and remove it with the minus button. Add it again with the plus button (or click **Allow** in **Settings > Recording**), and turn it on.
3. Quit and reopen GrokNola.
4. If you build the app yourself, run `./scripts/create-signing-cert.sh` once so later rebuilds keep the permission.

### No audio from your mic, or no call audio

If the microphone meter stays flat or turns red with "No audio from your mic":

1. Open **System Settings > Sound > Input** and check that the right device is selected and its input level moves when you talk.
2. Check that the microphone is not muted on the headset or in hardware.
3. If you changed devices during the call, stop and start notes again.

If the call-audio meter stays flat or shows "No call audio — is the meeting app playing through this Mac?":

1. Check that you can hear the other side on this Mac. Audio played on a phone or another device is not captured.
2. Check that **Screen & System Audio Recording** is on (see the next section).
3. Some apps play to a separate output device. Choose the same output in the meeting app and in **System Settings > Sound > Output**.

Both warnings are hints. A quiet listener or a long monologue can trigger them; the recording continues either way.

### Microphone error or echo cancellation message

- With system audio on, the app uses echo cancellation so remote voices from your speakers are not transcribed as you. macOS echo cancellation works with the default input and output in **System Settings > Sound**. Some device combinations, such as some Bluetooth headsets, still refuse it.
- Then the app records the plain microphone and shows "Echo cancellation isn't available with these devices, so GrokNola removes the call audio that your mic picks up from the speakers." Because the app also records the call audio, it drops your lines that repeat what someone on the call said at the same moment, while recording and again after the call. Short replies such as "yeah" are dropped only when the call had the same words at the same moment.
- Your own words spoken over someone else can still be lost or mixed in. Headphones give the cleanest result.
- If you always wear headphones, turn off **Settings > Recording > Echo cancellation**. That also turns off removing repeated call audio.
- "Could not start the microphone" means no input device is available or another app holds it. Check **System Settings > Sound > Input**, then start again.
- "GrokNola needs microphone access" means the Microphone permission is off. Turn it on in **System Settings > Privacy & Security > Microphone**.

### My voice is quiet

The app automatically raises a quiet microphone by up to 12 dB while recording. In playback, keep **Balance voices** on in the player's voice levels panel, or raise **My voice** (or lower **Others**).

### Names are not detected (everyone is "Them")

- Active-speaker names and snapshots are off by default. Turn on **Read who is talking from the meeting app** or **Identify speakers from meeting-window snapshots** in **Settings > Speakers** if your company allows it.
- Check **Accessibility** and **Screen & System Audio Recording** in **Settings > Recording**. Active-speaker names and snapshots need system audio.
- Start notes while the call is open, so the meeting app is detected (the button reads **Start notes · <App>**).
- Make sure **Let Grok infer names from the conversation** and **Identify speakers live** are on.
- A calendar event with invitees helps a lot, especially in one-on-ones.
- Rename speakers yourself. Your names are remembered for later meetings. Then choose **Regenerate Notes** (Option-Command-R) to rewrite the notes with the names.

### Calendar is stale or empty

- Check the status line in **Settings > Calendar & Drive**, then click **Reload**.
- "Google access ended" means the sign-in was revoked or expired. Click **Connect Google Calendar** again.
- "Google sign-in timed out" means the browser step was not finished within 5 minutes. Try again.
- For Apple Calendar, allow the Calendar permission and set the source to **Apple Calendar** or **Automatic**.

### Google Drive copies are missing

Settings says "Drive not found" when Google Drive for desktop is not installed, not signed in, or not mounted under `~/Library/CloudStorage`. Open Google Drive for desktop and sign in. If it says "Pick a Drive account", choose one under **Drive account**. The app keeps saving locally. Copies are made on the next save of each meeting after recording stops.

### Recording won't start

- "GrokNola doesn't record meetings with people at blocked domains." The invite lists someone at a blocked domain. See [Before recording starts](#before-recording-starts).
- "GrokNola records only internal meetings." The invite lists people outside your company domains and **Record** is **Internal meetings only**. Check **Company email domains** in **Settings > Privacy & Data**.
- "This pilot build records only when FileVault is on." Turn on FileVault in **System Settings > Privacy & Security > FileVault**, then start again.
- Clicking **Cancel** in the consent confirmation does not record anything.

### Other messages

- "Add your xAI API key in Settings" means no key is saved. See [Getting started](#getting-started).
- "Transcribing full recording failed: Kept the live transcript." The notes still use the live transcript.
- "Writing notes failed" in the Notes tab means a request failed. Click **Retry** (or **Write notes**, or **Regenerate Notes** in the **More** menu) to try again.
- "Tagging failed" or "Naming speakers failed": click **Retry** next to the message.
- "The audio for this meeting is no longer on this Mac." means the audio was not kept or was deleted by the retention setting.
