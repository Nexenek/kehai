import '../../../data/services/notifications/kehai_sound.dart';
import '../../../domain/models/ping.dart';

/// Centralized user-facing copy. Keeping every string here (instead of
/// inline in widgets) means swapping to real l10n (ARB files, per
/// design-language.md "Polish + English localization from day one") later
/// is a mechanical move, not a rewrite. Voice: warm, plain, sentence case,
/// kaomoji accents, honest errors — see kb/design-language.md.
///
/// The two imports above are the only ones this file has, and both are
/// enums it switches on to keep per-kind copy (ping kinds, notification
/// event types) in here rather than scattered across the widgets — the
/// point of the file.
class AppStrings {
  const AppStrings._();

  // App
  static const appName = 'Kehai';

  // Onboarding — server step
  static const serverStepTitle = 'find your server';
  static const serverStepBody =
      "enter the address of your home server (or its Tailscale name). "
      "we'll just say hi first — nothing is sent until you log in.";
  static const serverUrlLabel = 'server address';
  static const serverUrlHint =
      'https://100.x.x.x:8090 or https://couples.tail...ts.net';
  static const testConnection = 'test connection';
  static const connectionOk = "found it! (｡•̀ᴗ-)✧";
  static const connectionFailed =
      "couldn't reach your server (・_・;) — check the address or Tailscale?";
  static const continueLabel = 'continue';

  // Onboarding — auth step
  static const authStepTitle = 'sign in';
  static const authStepBodyLogin = 'welcome back — sign in to your account.';
  static const authStepBodyRegister = "let's make you an account.";
  static const emailLabel = 'email';
  static const passwordLabel = 'password';
  static const nameLabel = 'your name';
  static const loginButton = 'sign in';
  static const registerButton = 'create account';
  static const switchToRegister = "new here? create an account";
  static const switchToLogin = 'already have an account? sign in';
  static const authFailed = "hmm, that didn't work (￣ヘ￣) — check your details?";

  // Onboarding — couple step
  static const coupleStepTitle = 'start our couple';
  static const coupleStepBody =
      "make a new couple space, or join your partner's with their code.";
  static const createCoupleButton = 'start a new couple';
  static const joinCoupleButton = 'join with a code';
  static const coupleNameLabel = 'what should we call you two?';
  static const coupleNameHint = 'e.g. "us", "kuba & mati"';
  static const createButton = 'create';
  static const joinButton = 'join';
  static const inviteCodeLabel = 'invite code';
  static const inviteCodeExplainer =
      'send this to your person so they can join ヾ(＾-＾)ノ';
  static const copyCode = 'copy';
  static const codeCopied = 'copied! (｡♥\uFE0E‿♥\uFE0E｡)';
  static const back = 'back';
  static const enterCodeLabel = 'their invite code';
  static const enterCodeHint = 'e.g. AB12CD';
  static const coupleFailed =
      "that didn't go through (・_・;) — double check the code and try again?";

  // Home
  static const waitingTitle = 'waiting for your person';
  static const waitingBody =
      'send them your invite code and they can join any time.';
  static const waitingKaomoji = '(づ￣ ³￣)づ';
  static const partnerCardTitleFallback = 'your person';
  static const updatedJustNow = 'updated just now';
  static const moodPickerTitle = 'how are you feeling?';
  static const noteHint = 'add a little note… (optional)';
  static const saveNote = 'save';
  static const noteSaved = 'saved (｡•̀ᴗ-)✧';
  static const onPhoneTooltip = 'on their phone';
  static const onDesktopTooltip = 'at their computer';
  static const onBothTooltip = 'on their phone and their computer';
  static const offlineTooltip = 'no devices seen recently';
  static const logOut = 'log out';
  static const inviteCodeShort = 'invite code';

  // Home — partner card ambient line (kb/platform-desktop.md "Telemetry
  // contract": now_playing > activity > "at their computer"/"on their
  // phone" > "away" > nothing recent).
  static const ambientAtComputer = onDesktopTooltip;
  static const ambientOnPhone = onPhoneTooltip;
  static const ambientAway = 'away (￣～￣;)';
  static const ambientAsleep = 'probably asleep ( ᴗ˳ᴗ ) zzZ';
  static const batteryLowTooltip = 'battery low';
  static const chargingTooltip = 'charging';

  // Home — desktop companion tray (kb/platform-desktop.md "Desktop
  // companion layout"): the bottom bar in the compact window, whose
  // sections slide up as a drawer.
  static const trayMood = 'mood';
  static const trayDoodle = 'doodle';
  static const trayCountdowns = 'countdowns';
  static const trayNotes = 'notes';
  static const trayCloseTooltip = 'close';
  static String trayOpenTooltip(String section) => 'open $section';

  // Home — tray overflow redesign (2026-08-23): five primaries (mood,
  // doodle, pet, thumb-kiss, ✚ more) plus a grid behind ✚ for the rest —
  // ten sections no longer fit five buttons. Grid tiles reuse the labels
  // above (trayCountdowns/trayNotes/trayInstants/trayMap) plus these two.
  static const trayPet = 'pet';
  static const trayThumbKiss = 'kiss';
  static const trayMore = 'more';
  static const trayBoard = 'board';
  static const trayQuestion = 'question';
  static const trayBackToMoreTooltip = 'back to more';

  // Desktop window chrome — our own title bar in place of the OS one.
  // Neither control ends the app: Kehai lives in the tray, so ★ and ♥ both
  // fold the window back into the little always-there card.
  static const minimizeTooltip = 'tuck us away ★';
  static const closeWindowTooltip = 'back to the little window ♥\uFE0E';

  // Desktop tray — the pixel heart that's always there.
  static const trayTooltip = 'Kehai — czuję, że tam jesteś';
  static const trayOpen = 'open kehai ♡\uFE0E';
  static const trayMini = 'just the little one';
  static const trayAutostart = 'start with the computer';
  static const trayQuit = 'quit for real';

  // The little window (mini state).
  static const miniExpandTooltip = 'open the big window ♡\uFE0E';
  static const miniDragHint = 'drag me anywhere';
  static const miniNobodyYet = 'nobody here yet (｡•ᴗ•｡)';

  // Home — always-on-top pin. Honest about Wayland: we can ask, but the
  // compositor decides (see kb/platform-desktop.md).
  static const alwaysOnTopOffTooltip =
      'keep us on top of your other windows ✦ '
      '(on wayland the compositor may quietly ignore this)';
  static const alwaysOnTopOnTooltip =
      'let other windows cover us again ✦ '
      '(on wayland the compositor may quietly ignore this)';

  // Home — countdowns
  static const countdownsTitle = 'countdowns';
  static const countdownsEmpty =
      "nothing counted down yet… add something to look forward to! (￣ω￣)";
  static const addCountdown = 'add';
  static const countdownToday = 'today!! ✧';
  static String countdownInDays(int days) =>
      'in $days ${days == 1 ? 'day' : 'days'}';
  static String countdownDaysAgo(int days) =>
      '$days ${days == 1 ? 'day' : 'days'} ago';
  static const countdownTitleLabel = 'what are we counting down to?';
  static const countdownTitleHint = 'e.g. "trip to kyoto"';
  static const countdownDateLabel = 'date';
  static const countdownKaomojiLabel = 'kaomoji (optional)';
  static const countdownKaomojiHint = 'e.g. ✈ or (๑˃ᴗ˂)ﻭ';
  static const newCountdownTitle = 'new countdown';
  static const editCountdownTitle = 'edit countdown';
  static const saveCountdown = 'save';
  static const deleteCountdown = 'delete';

  // Home — together / anniversary
  static String togetherDays(int days) =>
      'together $days ${days == 1 ? 'day' : 'days'} ♡\uFE0E';
  static const setAnniversary = 'set your day ♡\uFE0E';
  static const anniversaryDialogTitle = 'your day together';
  static const anniversaryDialogBody = 'when did you two get together?';
  static const saveAnniversary = 'save';
  static const editTooltip = 'edit';

  // Home — notes
  static const notesTitle = 'notes';
  static const notesEmpty = "no notes yet… stick something up! (｡•ᴗ•｡)";
  static const addNote = 'add';
  static const noteTitleLabel = 'title';
  static const noteTitleHint = 'optional title';
  static const noteBodyLabel = 'note';
  static const noteBodyHint = 'write something sweet…';
  static const noteColorLabel = 'color';
  static const notePinLabel = 'pin this note';
  static const newNoteTitle = 'new note';
  static const editNoteTitle = 'edit note';
  static const saveNoteButton = 'save';
  static const deleteNoteButton = 'delete';
  static const untitledNote = 'untitled';

  // Home — doodles
  static const doodleDialogTitle = 'draw something for them ♡\uFE0E';
  static const doodleUndo = 'undo';
  static const doodleClear = 'clear';
  static const doodleSend = 'send';
  static const doodleSending = 'sending…';
  static const doodleSent = 'sent! (｡•̀ᴗ-)♡\uFE0E';
  static const doodleSendFailed = "couldn't send that (・_・;) — try again?";
  static const sendDoodleTooltip = 'send a doodle ✎';
  static const drawBackButton = 'draw back ✎';
  static const deleteDoodleTooltip = 'delete this doodle';
  static const brushSmallTooltip = 'small brush';
  static const brushBigTooltip = 'big brush';
  static String fromThemCaption(String relative) => 'from them · $relative';
  static String youSentCaption(String relative) => 'you sent · $relative';

  // Home — location (kb/contracts.md "Location", ADR-6). Voice rule from
  // design-language.md: "Privacy controls use honest language: ghost mode
  // says 'Location paused — partner can see it's paused'." Nothing here
  // guilts anyone for pausing, and nothing implies secret tracking.
  static const locationTitle = 'where we are';
  static const locationEmpty = 'no location yet ( . .)';
  static const locationEmptyHint =
      "once OwnTracks is pointed at your server, your dots show up here.";
  static const locationYou = 'you';
  static const locationRecenter = 'centre on us';
  static const mapAttribution = '© OpenStreetMap';

  /// Per-marker freshness chip: "you · 5m ago", "mati · just now".
  static String locationAsOf(String who, String relative) => '$who · $relative';

  // Distance-apart (kb/contracts.md: "~X km apart ♡").
  static String distanceApart(String km) => '~$km km apart ♡\uFE0E';
  static const distanceTogether = 'right here together ♡\uFE0E';

  // Their pause, seen from my side — honest, never accusing.
  static String partnerGhostUntil(String name, String when) =>
      "$name's location is paused — until $when";
  static String partnerGhostIndefinite(String name) =>
      "$name's location is paused — until they turn it back on";

  // My own sharing switch.
  static const ghostRowSharing = 'your location: sharing ♡\uFE0E';
  static String ghostRowPausedUntil(String when) =>
      'your location: paused until $when';
  static const ghostRowPausedIndefinite =
      'your location: paused until you turn it back on';
  static const ghostExplainer =
      "pausing is honest — they see that it's paused, not a dot quietly "
      "going stale.";
  static const ghostPauseHour = '1h';
  static const ghostPauseTomorrow = 'until tomorrow';
  static const ghostPauseIndefinite = 'until I turn it on';
  static const ghostResume = 'sharing on';
  static const ghostPauseHourTooltip = 'pause sharing for an hour';
  static const ghostPauseTomorrowTooltip =
      'pause sharing until 8:00 tomorrow morning';
  static const ghostPauseIndefiniteTooltip =
      'pause sharing until you turn it back on yourself';
  static const ghostResumeTooltip = 'share your location again';
  static const ghostFailed =
      "couldn't change that just now (・_・;) — try again?";

  // Tray button for the map section.
  static const trayInstants = 'photos';
  static const trayMap = 'map';
  static const trayArt = 'our art';
  static const trayFiles = 'files';

  // Ongoing notification (Android) — the pocket version of the partner
  // window. Composed in Dart (see buildPartnerNotification) and handed to
  // the foreground service to render.
  static const notificationChannelName = 'partner window';
  static const notificationChannelDescription =
      'the quiet always-there note showing how your person is doing. '
      'silent, and it stays put while Kehai is watching.';
  static const notificationStartingTitle = appName;
  static const notificationStartingText = 'looking for your person… (｡•ᴗ•｡)';
  static const notificationWaitingTitle = 'waiting for your person';
  static const notificationWaitingText =
      "we'll fill this in the moment they're around ♡\uFE0E";
  static const notificationDevicesPhone = 'phone';
  static const notificationDevicesDesktop = 'computer';
  static const notificationDevicesBoth = 'phone · computer';
  static const notificationDevicesNone = offlineTooltip;

  // Phone superpowers (Android permissions/onboarding screen).
  static const superpowersTitle = 'phone superpowers';
  static const superpowersOpen = 'phone superpowers ✧';
  static const superpowersIntro =
      "none of this is required — Kehai works without any of it, it just "
      "has less to tell them. turn on only what feels okay, and turn it "
      "back off in system settings whenever you like.";
  static const superpowersGrant = 'turn on';
  static const superpowersGranted = 'on ✓';
  static const superpowersUnavailable = 'not on this device';
  static const superpowersRefresh = 'check again';
  static const superpowersDone = 'done';

  static const superpowerNotificationsTitle = 'show the partner window';
  static const superpowerNotificationsBody =
      "lets Kehai keep one silent notification pinned with your person's "
      "mood, note and what they're up to. it's the only notification we "
      "post, and it never makes a sound.";

  static const superpowerBatteryTitle = 'stay awake in the background';
  static const superpowerBatteryBody =
      "asks android to stop putting Kehai to sleep, so their window keeps "
      "updating while your phone is in your pocket. without it your phone "
      "may go quiet to them after a while. some phones need extra steps in "
      "their own battery settings — dontkillmyapp.com has the recipe.";

  static const superpowerListenerTitle = 'share what you\'re listening to';
  static const superpowerListenerBody =
      "android calls this \"notification access\". it lets Kehai read your "
      "media players — title, artist, album, and whether it's playing — so "
      "your person sees ♪ on your card. the honest part: this permission "
      "technically exposes every notification on your phone to Kehai. we "
      "only read media sessions, we never store or send anything else, and "
      "you can revoke it in settings any second.";

  static const superpowerServiceTitle = 'keep watch while backgrounded';
  static const superpowerServiceBody =
      "runs the little background helper that sends your status and keeps "
      "their window fresh when Kehai isn't the app you're looking at.";
  static const superpowerServiceRunning = 'running ♡\uFE0E';
  static const superpowerServiceStopped = 'off';
  static const superpowerServiceStart = 'start';
  static const superpowerServiceStop = 'stop';
  static const superpowersOpenSettingsFailed =
      "couldn't find that settings screen (・_・;) — your phone may hide it.";

  static const superpowerUsageAccessTitle = 'share what app you\'re in';
  static const superpowerUsageAccessBody =
      "android calls this \"usage access\". it lets Kehai see which app is "
      "in front right now, so your person's card can say something like "
      "\"coding ⌨\uFE0E\" or \"gaming\" instead of just \"on their phone\". we "
      "only ever read the current app's name — never anything on screen — "
      "and you can revoke it in settings any second.";

  static const shareFocusedAppTitle = 'share what app you\'re focused on';
  static const shareFocusedAppBody =
      "tells them what app you're focused on, like \"coding ⌨\uFE0E\" or "
      "\"gaming\" — off means we never look. it sits one rung below "
      "now-playing, so if you're mid-song it says that instead.";
  static const shareFocusedAppOn = 'sharing ✓';
  static const shareFocusedAppOff = 'off';
  static const shareFocusedAppTurnOn = 'turn on';
  static const shareFocusedAppTurnOff = 'turn off';

  static const superpowerLocationPermissionTitle = 'allow location access';
  static const superpowerLocationPermissionBody =
      "android makes us ask this in two steps, on purpose. first \"while "
      "using the app\" — that alone only reports while Kehai is on screen. "
      "then, if you want your dot to keep updating in the background too, "
      "a separate \"allow all the time\" step that opens your phone's own "
      "settings. skip step two and location just goes quiet the moment you "
      "leave Kehai.";
  static const superpowerLocationPermissionWhileInUseOnly = 'while using only';
  static const superpowerLocationPermissionOff = 'off';
  static const superpowerLocationGrantWhileInUse = 'allow while using';
  static const superpowerLocationGrantAlways = 'allow all the time';

  static const shareLocationTitle = 'share my location ♡';
  static const shareLocationBody =
      "puts a little dot for you on the couple map — the same "
      "\"/api/owntracks\" route the separate OwnTracks app already uses, so "
      "you never have to run both. pausing it is called ghost mode and "
      "lives in the map window, not here; turning this off just means we "
      "stop asking your phone for a fix at all.";

  static const shareUnknownAppsTitle = 'guess at apps we don\'t know';
  static const shareUnknownAppsBody =
      "we only recognize a couple dozen apps by name. turn this on and an "
      "app we don't know still shows a cleaned-up guess at its name — off, "
      "and an unrecognized app just says nothing at all.";

  // Desktop sharing settings (the ✧ in the title bar).
  static const sharingSettingsTitle = 'sharing ✧';
  static const sharingSettingsTooltipOff =
      'sharing settings — nothing extra on';
  static const sharingSettingsTooltipOn =
      'sharing settings — telling them what app you\'re in ✧';
  static const sharingSettingsIntro =
      "controls what your devices tell your person, beyond the basics. "
      "everything here is off by default.";
  static const sharingSettingsDone = 'done';

  // Generic
  static const loading = 'one sec… (｡•ᴗ•｡)';
  static const genericError = "something went sideways (；一_一) — try again?";
  static const retry = 'try again';
  static const cancel = 'cancel';

  // Home — instants (kb/contracts.md "Instants": quick photos shared
  // through the day). Not wired into the home tray/layout in this batch —
  // see the top-of-file note in ui/features/instants/instants_window.dart.
  static const instantsTitle = 'instants';
  static const instantsEmpty =
      "no instants yet — show them your day! (´｡• ᵕ •｡`)";
  static const sendInstant = 'send an instant';
  static const sendInstantTooltip = 'send an instant';
  static const sendInstantDialogTitle = 'send an instant';
  static const instantCaptureCamera = 'camera';
  static const instantCaptureGallery = 'gallery';
  static const instantChoosePhoto = 'choose a photo';
  static const instantChangePhoto = 'choose a different one';
  static const instantCaptionHint = 'add a caption… (optional)';
  static const instantSend = 'send';
  static const instantSending = 'sending…';
  static const instantSent = 'sent! (｡•̀ᴗ-)♡\uFE0E';
  static const instantSendFailed = "couldn't send that (・_・;) — try again?";
  static const instantPickFailed =
      "couldn't get that photo (・_・;) — try again?";
  static const deleteInstantTooltip = 'delete this instant';
  static const instantsLoadMore = 'load more';

  // Home — dual clocks (kb/features.md "Timezone dual clocks"). The line
  // only shows when the partner's freshest device offset differs from
  // mine; ☾/☀ reflects whether it's currently night/day for them, not a
  // decoration.
  static String theirTimeLine(String time, String glyph) =>
      'their time: $time $glyph';

  // Home — thumb-kiss (kb/features.md "Thumb-kiss"). Copy sets latency
  // expectations honestly, per design-language.md's "errors are honest and
  // gentle" voice rule — realtime lag here isn't a bug, so we say so.
  static const thumbKissTitle = 'thumb-kiss';
  static const thumbKissHint = 'hold your thumb here… feel for them ♡';
  static const thumbKissMetMessage = 'you found each other ♡';
  static const thumbKissLatencyHint =
      "a little lag is normal — it's really them, just a beat behind";

  // Home — the shared pet (kb/features.md "Shared pet"). The hard rule from
  // that file's anti-features list: "The pet gets 'sleepy', never dies." So
  // nothing in this block nags, scolds, warns or counts down to anything
  // bad. The most negative line we ever show is wistful — "dreaming of
  // snacks…" — and the pet is always waiting patiently, never suffering.
  // Not wired into the home tray/layout in this batch — see the
  // top-of-file note in ui/features/pet/pet_window.dart.
  static const petTitle = 'our pet';
  static const petDefaultName = 'kehai-chan';
  static const petAdopting = 'waking them up… (｡•ᴗ•｡)';
  static const petUnavailable =
      "your pet is napping somewhere we can't reach (・_・;) — try again in "
      "a bit?";
  static const petActionFailed =
      "that didn't reach your server (・_・;) — they're fine, try again?";

  // Care buttons.
  static const petFeed = 'feed ♡︎';
  static const petPet = 'pet';
  static const petDress = 'dress ▾';
  static const petRename = 'rename';
  static const petFeedTooltip = 'give them a snack';
  static const petPetTooltip = 'give them a cuddle';
  static const petDressTooltip = 'change how they look';
  static const petRenameTooltip = 'give them a new name';

  // Derived state lines (ui/features/pet/pet_state.dart): hunger from how
  // long since the last snack, cuddles from the last pet, plus a 23:00–07:00
  // nap. None of these is a failure state — there is no failure state.
  static const petLineFullCozy = 'full and cosy ♡︎ (´｡• ᵕ •｡`)';
  static const petLineFullCuddles = 'full ♡︎ — and up for a cuddle (｡･ω･｡)';
  static const petLinePeckishCozy = 'peckish, but comfy (｡•ᴗ•｡)';
  static const petLinePeckishCuddles = 'peckish, and cuddle-shaped (｡•ᴗ•｡)';
  static const petLineHungryCozy = 'dreaming of snacks… (￣ω￣)';
  static const petLineHungryCuddles = 'dreaming of snacks and cuddles… (￣ω￣)';
  static const petLineSleepy = 'fast asleep (￣o￣) zzZ';
  static const petLineSleepyHungry = 'dreaming of snacks… (￣o￣) zzZ';

  // Dress-up dialog.
  static const petDressTitle = 'dress up';
  static const petVariantLabel = 'who are they?';
  static const petOutfitLabel = 'what are they wearing?';
  static const petVariantBlob = 'blob';
  static const petVariantCat = 'cat';
  static const petVariantStar = 'star';
  static const petOutfitNone = 'nothing';
  static const petOutfitBow = 'bow';
  static const petOutfitScarf = 'scarf';
  static const petOutfitCrown = 'crown';
  static const petDressSave = 'save';

  // Rename dialog.
  static const petRenameTitle = 'their name';
  static const petNameLabel = 'name';
  static const petNameHint = 'e.g. "kehai-chan"';
  static const petRenameSave = 'save';

  // Focused-app sharing preview ("what we'd share right now" — bug-fix pass
  // on kb/features.md "Focused-app status", 2026-08-23): a live status line
  // under the desktop sharing-settings toggles and the Android superpowers
  // screen's matching window, so a silent failure (Wayland/GNOME with no
  // window reader, Usage Access revoked, an app with no mapping-table entry)
  // is visible instead of the partner's card just... never saying anything.
  static const sharingPreviewOff = 'sharing is off — we never look';
  static const sharingPreviewNoReading =
      "can't see the focused window on this desktop (・_・;)";
  static const sharingPreviewNoReadingAndroid =
      "can't see the focused app right now (・_・;)";
  static const sharingPreviewUnmapped =
      "this app isn't on the list — sharing nothing (turn on 'unknown apps' "
      "to share its name)";
  static String sharingPreviewSharing(String label) =>
      "right now they'd see: $label";
  static const sharingPreviewGrantUsageAccess =
      'grant usage access first (・_・;)';

  // Home — daily question, blind reveal (kb/features.md: "both answer
  // blind, reveal together — ritual + conversation fuel"). Not wired into
  // the home tray/layout in this batch — see the top-of-file note in
  // ui/features/questions/daily_question_window.dart. Anti-features rule:
  // no streaks, no "you missed a day" — a missed day is simply never
  // mentioned anywhere in this copy.
  static const questionsTitle = 'daily question';
  static const questionsLoading = "finding today's question… (｡•ᴗ•｡)";
  static const questionsAnswerHint = 'type your answer…';
  static const questionsSubmit = 'seal it ✉';
  static const questionsUpdateAnswer = 'update your answer';
  static const questionsWaitingTitle = 'sealed until you both answer';
  static const questionsWaitingBody = '✉ waiting for them…';
  static const questionsYourAnswerLabel = 'you said';
  static const questionsPartnerAnswerLabel = 'they said';
  static const questionsRevealedTitle = 'you both answered! ♡';
  static const questionsLoadFailed =
      "couldn't find today's question (・_・;) — try again?";
  static const questionsSubmitFailed = "that didn't send (・_・;) — try again?";

  // Home — shared board (kb/features.md "Shared board": a freeform
  // decorable pinboard both partners arrange together). Not wired into the
  // home tray/layout in this batch — see the top-of-file note in
  // ui/features/board/board_window.dart.
  static const boardTitle = 'our board';
  static const boardEmpty =
      "an empty board… let's fill it together (´｡• ᵕ •｡`)";
  static const boardAdd = 'add';
  static const boardAddMenuTitle = 'add to the board';
  static const boardAddNote = 'note ✎';
  static const boardAddPhoto = 'photo ◉';
  static const boardAddSticker = 'sticker ♥︎';
  static const boardNoteDialogTitle = 'pin a note';
  static const boardPhotoDialogTitle = 'pin a photo';
  static const boardStickerDialogTitle = 'pick a sticker';
  static const boardDeleteItemTooltip = 'remove this from the board';

  // Art system (ADR-13 paper-doll layers, kb/features.md "Status art
  // system"). Written for the artist, who is not a programmer: no "assets",
  // no "z-index", no "conditions" — just drawings, slots, and "show it
  // when". Not wired into the home tray/layout in this batch — see the
  // top-of-file note in ui/features/art/art_window.dart.
  static const artTitle = 'our art ✎';
  static const artLoading = 'looking for your drawings… (｡•ᴗ•｡)';
  static const artEmpty =
      "no drawings yet. draw them a little you, and they'll see it in "
      "their window ♡\uFE0E";

  // Slots — the artist's words for the paint order.
  static const artSlotBackground = 'background';
  static const artSlotBase = 'body';
  static const artSlotOutfit = 'outfit';
  static const artSlotExpression = 'face';
  static const artSlotProp = 'prop';
  static const artSlotBackgroundHint = 'the room behind them';
  static const artSlotBaseHint = 'the pose everything else sits on';
  static const artSlotOutfitHint = 'what they are wearing';
  static const artSlotExpressionHint = 'eyes and mouth';
  static const artSlotPropHint = 'a mug, headphones, the cat';
  static const artSlotEmpty = 'nothing here yet';
  static const artBaseMissing =
      "add one drawing to \"body\" and the scene switches on — until then "
      "their window keeps the kaomoji (´｡• ᵕ •｡`)";

  // Adding a layer.
  // Short, because it sits inline next to each slot's name; the dialog it
  // opens carries the full sentence.
  static const artAddLayer = 'add';
  static const artAddDialogTitle = 'add a drawing';
  static const artChooseFile = 'choose a PNG';
  static const artChangeFile = 'pick a different one';
  static const artPickFailed = "couldn't open that file (・_・;) — try again?";
  static const artNotPng =
      "that isn't a PNG. layers have to be see-through, and only PNG can "
      "be — a JPG would cover everything under it";
  static const artTooBig =
      'that file is over 2 MB — big for a drawing this small. try saving '
      'it again at 512×512?';
  static const artEmptyFile = "that file came back empty (・_・;)";
  static const artUploadFailed = "that didn't upload (・_・;) — try again?";
  static const artUploading = 'sending…';
  static String artNotSquareWarning(String size) =>
      "heads up: this one is $size, not square — it'll be squeezed to fit "
      'the same canvas as the others';

  // Layer editor.
  static const artLayerDialogTitle = 'this drawing';
  static const artNameLabel = 'call it something';
  static const artNameHint = 'e.g. "sleepy eyes"';
  static const artWhenMoodsLabel = 'show it when they feel…';
  static const artWhenAmbientLabel = 'and when they are…';
  static const artAnyHint = 'nothing ticked = any time';
  static const artDefaultToggle = 'fall back to this one';
  static const artDefaultHint =
      'used when nothing more specific fits — one per slot is plenty';
  static const artSave = 'save';
  static const artDelete = 'delete';
  static const artDeleteTooltip = 'delete this drawing';
  static const artMoveUpTooltip = 'move up (picked first on a tie)';
  static const artMoveDownTooltip = 'move down';
  static const artEditTooltip = 'edit this drawing';

  // Ambient states, in the artist's words.
  static const artAmbientMusic = 'listening to music';
  static const artAmbientAway = 'away';
  static const artAmbientPhone = 'on their phone';
  static const artAmbientComputer = 'at their computer';
  static const artAmbientActivity = 'busy in an app';
  static String artAmbientLabel(String kind) => switch (kind) {
    'music' => artAmbientMusic,
    'away' => artAmbientAway,
    'phone' => artAmbientPhone,
    'computer' => artAmbientComputer,
    'activity' => artAmbientActivity,
    _ => kind,
  };

  // Live preview — the artist's feedback loop.
  static const artPreviewTitle = 'preview';
  static const artPreviewMoodLabel = 'if they felt…';
  static const artPreviewAmbientLabel = 'and they were…';
  static const artPreviewAmbientAny = 'nothing in particular';
  static const artPreviewNoScene =
      "nothing fits this one yet — their window would show the kaomoji";

  // How-to, for the non-technical half of the couple.
  static const artHowToTitle = 'how the layers work';
  static const artHowToBody =
      'draw everything on the same square canvas — 512×512 is a good size '
      '— and save each piece as its own see-through (transparent) PNG.\n\n'
      'the app stacks them in this order, every time:\n'
      'background → body → outfit → face → prop\n\n'
      'only one drawing per slot is on screen at once. you tell each one '
      'when to show up (a mood, what they are doing, or nothing at all for '
      '"any time"), and the app picks the one that fits them right now — '
      'most specific wins, then whatever is highest in the list.\n\n'
      'Pixelorama is free and open source, runs in a browser, and exports '
      'exactly these PNGs ♡\uFE0E';

  // Home — calendar (Phase 4b, kb/decisions.md ADR-7 deviation: a
  // kehai-native `calendar_events` collection for v1 instead of CalDAV —
  // see server/migrations/11_calendar.go). Tray glyph is
  // [PixelCalendarGlyph] (grid + heart), not '▦' — that text glyph is
  // already the board section's.
  static const trayCalendar = 'calendar';
  static const calendarTitle = 'calendar';
  static const calendarTodayButton = 'today';
  static const calendarPrevMonthTooltip = 'previous month';
  static const calendarNextMonthTooltip = 'next month';

  // Weekday header, Monday-first (Polish convention).
  static const calendarWeekdayMon = 'Mo';
  static const calendarWeekdayTue = 'Tu';
  static const calendarWeekdayWed = 'We';
  static const calendarWeekdayThu = 'Th';
  static const calendarWeekdayFri = 'Fr';
  static const calendarWeekdaySat = 'Sa';
  static const calendarWeekdaySun = 'Su';
  static const calendarWeekdayHeaders = [
    calendarWeekdayMon,
    calendarWeekdayTue,
    calendarWeekdayWed,
    calendarWeekdayThu,
    calendarWeekdayFri,
    calendarWeekdaySat,
    calendarWeekdaySun,
  ];

  // The upcoming strip under the grid: "in 3 days · dinner date ♡".
  static const calendarUpcomingEmpty =
      "nothing coming up yet… plan a little something? (｡•ᴗ•｡)";
  static String calendarUpcomingRow(String dayLabel, String title) =>
      '$dayLabel · $title ♡\uFE0E';

  // Tapping a day opens its event list.
  static const calendarDayEmpty =
      "nothing planned this day yet… add something? ( ・ᴗ・ )";
  static const calendarAllDayChip = 'all day';

  // Add/edit dialog.
  static const calendarNewEventTitle = 'new event';
  static const calendarEditEventTitle = 'edit event';
  static const calendarEventTitleLabel = "what's happening?";
  static const calendarEventTitleHint = 'e.g. "dinner date"';
  static const calendarAllDayLabel = 'all day';
  static const calendarStartsLabel = 'starts';
  static const calendarEndsToggle = 'add an end';
  static const calendarEndsLabel = 'ends';
  static const calendarNotesLabel = 'notes';
  static const calendarNotesHint = 'anything to remember… (optional)';
  static const calendarColorLabel = 'color';
  static const calendarAddEvent = 'add';
  static const calendarSaveEvent = 'save';
  static const calendarDeleteEvent = 'delete';

  // Home — shared file storage (kb/features.md "Shared file storage": a
  // simple shared drive backed by a Protected PocketBase file field —
  // server/migrations/12_files.go). Not wired into the home tray/layout in
  // this batch — see the top-of-file note in ui/features/files/files_window.dart.
  static const filesTitle = 'our files';
  static const filesEmpty = "a little shelf for the two of you (´｡• ᵕ •｡`)";
  static const filesUpload = 'add a file';
  static const filesUploading = 'sending…';
  static const filesLoadMore = 'more';
  static const filesUploadFailed = "that didn't send (・_・;) — try again?";
  static const filesTooBig =
      "that file's too big — kehai keeps shared files to 100MB or less";
  static const filesPickFailed = "couldn't read that file (・_・;) — try again?";
  static const filesOpenFailed = "couldn't open that file (・_・;) — try again?";
  static const filesDeleteTooltip = 'remove this file';
  static const filesDeleteConfirmTitle = 'delete this file?';
  static String filesDeleteConfirmBody(String label) =>
      'remove "$label" for both of you? this can\'t be undone.';
  static const filesDeleteConfirmCancel = 'cancel';
  static const filesDeleteConfirmDelete = 'delete';
  static String filesYouCaption(String relative) => 'you · $relative';
  static String filesThemCaption(String relative) => 'them · $relative';

  // ==========================================================================
  // Pings, notifications and sounds (kb/features.md: "One-tap 'thinking of
  // you' ping", "Custom notification sounds"; kb/roadmap.md's client-side
  // notifications v1). Appended at the very end — see the file header.
  // ==========================================================================

  // --- the ping button ---

  /// U+FE0E after every heart: the text presentation selector, which stops
  /// Android substituting a colour emoji glyph for our pixel-ish one. Same
  /// convention as the rest of this file.
  static const pingButtonLabel = 'thinking of you ♡︎';
  static const pingSentLabel = 'sent ♡︎';
  static const pingKindTooltip = 'send something else…';
  static const pingKindPickerTitle = 'send them…';
  static const pingMiniTooltip = 'thinking of you ♡︎';

  /// The quiet line on the partner card when one of theirs lands. Reads as
  /// a sentence per kind rather than "they sent <label>", which turns
  /// "thinking of you" into nonsense.
  static String pingReceivedLine(PingKind kind) => switch (kind) {
    PingKind.thinking => "${kind.kaomoji}  they're thinking of you",
    PingKind.kiss => '${kind.kaomoji}  they sent you a kiss',
    PingKind.hug => '${kind.kaomoji}  they sent you a hug',
  };

  // --- notification copy ---
  //
  // Titles name the person (that's what you read on a lock screen); bodies
  // carry the feeling. Same warm/plain/sentence-case voice as everything
  // else — a notification is still Kehai talking.

  /// When we somehow don't have their name yet.
  static const notifyFallbackName = 'your person';

  /// The Linux toast's default action label ("clicking the notification
  /// does this"). Some daemons show it as a button, most just use it for
  /// the click.
  static const notifyOpenAction = 'open kehai';

  static String notifyPingTitle(String name) => '$name ♡︎';

  static String notifyPingBody(PingKind kind) => switch (kind) {
    PingKind.thinking => 'thinking of you (´｡• ᵕ •｡`)',
    PingKind.kiss => 'sent you a kiss (´ε｀ )♡︎',
    PingKind.hug => 'sent you a hug (づ￣ ³￣)づ',
  };

  static String notifyDoodleTitle(String name) => '$name drew you something';
  static const notifyDoodleBody = 'a little doodle just landed ✎';

  static String notifyInstantTitle(String name) => '$name sent an instant';
  static const notifyInstantBody = 'a moment from their day ◉';

  static const notifyRevealTitle = "today's question is open";
  static String notifyRevealBody(String name) =>
      '$name answered — go see what they said ✧';

  /// Android notification-channel names, as they appear in system settings.
  /// One per event type so the user can mute (or re-sound) exactly one kind
  /// of interruption from the OS side, without touching the others.
  static String notifyChannelName(KehaiEventKind kind) => switch (kind) {
    KehaiEventKind.ping => 'pings ♡︎',
    KehaiEventKind.doodle => 'doodles ✎',
    KehaiEventKind.instant => 'instants ◉',
    KehaiEventKind.reveal => 'daily question ✧',
  };

  static String notifyChannelDescription(KehaiEventKind kind) => switch (kind) {
    KehaiEventKind.ping =>
      'when they tap "thinking of you" (or send a kiss or a hug)',
    KehaiEventKind.doodle => 'when they draw you something',
    KehaiEventKind.instant => 'when they send a photo from their day',
    KehaiEventKind.reveal =>
      "when they answer today's question and the reveal opens",
  };

  // --- the sounds window ---

  static const soundsTitle = 'sounds ♪';
  static const soundsOpen = 'sounds ♪';
  static const soundsTooltip = 'pick a sound for each thing';
  static const soundsIntro =
      'pick what each thing sounds like. tap one to hear it ♪';
  static const soundsDone = 'done';

  static String soundsEventLabel(KehaiEventKind kind) => switch (kind) {
    KehaiEventKind.ping => 'a ping from them',
    KehaiEventKind.doodle => 'a doodle arrives',
    KehaiEventKind.instant => 'an instant arrives',
    KehaiEventKind.reveal => "today's question opens",
  };

  /// Shown under the picker on Android, where "preview" can't be anything
  /// but a real notification — see [KehaiNotifier.preview].
  static const soundsAndroidPreviewNote =
      "on android a preview is a real notification — it pops up and tidies "
      'itself away again ( ・ᴗ・ )';

  /// Shown on desktop when no audio player could be found at all.
  static const soundsNoPlayerNote =
      "couldn't find an audio player on this system (・_・;) — notifications "
      'will still show up, just quietly';

  static const soundsPreviewTitle = 'kehai ♪';
  static String soundsPreviewBody(String soundLabel) => 'this is "$soundLabel"';

  // --- mood changes deliberately do NOT notify ---
  //
  // Documented in code at KehaiEventKind's doc comment (the enum that lists
  // every event we WILL interrupt for) and surfaced to the user here, so
  // "why didn't it buzz when they went sleepy?" has an answer in the app
  // rather than only in the source.
  static const soundsAmbientNote =
      "moods, music and where they are don't make a sound — they live in "
      'their window, for whenever you look ♡︎';

  // --- smartwatch vitals (Health Connect steps + heart rate) ---

  /// Superpowers-screen row title + explainer. Vitals are the most intimate
  /// telemetry we carry, so the copy says exactly what leaves the phone.
  static const vitalsRowTitle = 'share heartbeat & steps ♥︎';
  static const vitalsRowBody =
      'lets them see your steps today and your latest heart rate from your '
      'watch (via health connect). only ever the newest reading — never '
      'history.';
  static const vitalsGrant = 'connect';
  static const vitalsNeedsHealthConnect =
      'health connect isn\'t available on this phone (´•ω•`)';
  static const vitalsNoData =
      'connected — waiting for your watch to sync something ♡︎';

  /// Partner-card vitals line pieces. bpm only renders while the sample is
  /// fresh (see HeartRateSample.freshWindow).
  static String vitalsBpm(int bpm) => '$bpm bpm';
  static String vitalsSteps(int steps) {
    // 4231 -> "4,231" — no intl dependency for one thousands separator.
    final s = steps.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '$b steps';
  }

  // --- the mood jar (leftovers wave) ---

  static const trayJar = 'jar';
  static const jarTitle = 'mood jar ⚱︎';
  static const jarEmpty =
      'the jar is empty so far — every mood you two set drops a little '
      'bead in here (´｡• ᵕ •｡`)';
  static const jarDayToday = 'today';
  static const jarDayYesterday = 'yesterday';

  // --- pet story (the append-only event log, finally readable) ---

  static const petHistoryButton = 'story';
  static const petHistoryTitle = 'the story so far';
  static const petHistoryEmpty =
      'nothing written yet — go say hi to the little one ヾ(＾-＾)ノ';

  // --- vitals grant fallbacks (appended: on-device hardening pass) -----
  //
  // Two honest failure modes the first build hid. Health Connect's
  // permission sheet doesn't always open (already-denied permissions stop
  // prompting; some ROMs skip it), and even when reads are granted the
  // separate "background" grant usually isn't — which quietly means vitals
  // only move while Kehai is on screen. Both now say so and offer the way
  // out rather than looking broken.

  /// Shown after a permission request came back with nothing granted; we
  /// deep-link to Health Connect's own settings at the same time.
  static const vitalsGrantFallback =
      "couldn't open the permission sheet — allow kehai's steps & heart "
      'rate in health connect, then come back ♡︎';

  /// Shown when the deep-link itself has nowhere to go.
  static const vitalsSettingsUnavailable =
      "couldn't find health connect's settings on this phone (´•ω•`)";

  /// The degraded-but-working state: reads granted, background reads not.
  static const vitalsForegroundOnly =
      'updates only while kehai is open — allow background access in health '
      'connect to keep it flowing ♡︎';

  /// Button on the two rows above.
  static const vitalsOpenSettings = 'open health connect ⚙︎';
}
