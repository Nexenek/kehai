/// Centralized user-facing copy. Keeping every string here (instead of
/// inline in widgets) means swapping to real l10n (ARB files, per
/// design-language.md "Polish + English localization from day one") later
/// is a mechanical move, not a rewrite. Voice: warm, plain, sentence case,
/// kaomoji accents, honest errors — see kb/design-language.md.
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
  static const codeCopied = 'copied! (｡♥‿♥｡)';
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

  // Desktop window chrome — our own title bar in place of the OS one.
  // Neither control ends the app: Kehai lives in the tray, so ★ and ♥ both
  // fold the window back into the little always-there card.
  static const minimizeTooltip = 'tuck us away ★';
  static const closeWindowTooltip = 'back to the little window ♥';

  // Desktop tray — the pixel heart that's always there.
  static const trayTooltip = 'Kehai — czuję, że tam jesteś';
  static const trayOpen = 'open kehai ♡';
  static const trayMini = 'just the little one';
  static const trayQuit = 'quit for real';

  // The little window (mini state).
  static const miniExpandTooltip = 'open the big window ♡';
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
      'together $days ${days == 1 ? 'day' : 'days'} ♡';
  static const setAnniversary = 'set your day ♡';
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
  static const doodleDialogTitle = 'draw something for them ♡';
  static const doodleUndo = 'undo';
  static const doodleClear = 'clear';
  static const doodleSend = 'send';
  static const doodleSending = 'sending…';
  static const doodleSent = 'sent! (｡•̀ᴗ-)♡';
  static const doodleSendFailed = "couldn't send that (・_・;) — try again?";
  static const sendDoodleTooltip = 'send a doodle ✎';
  static const drawBackButton = 'draw back ✎';
  static const deleteDoodleTooltip = 'delete this doodle';
  static const brushSmallTooltip = 'small brush';
  static const brushBigTooltip = 'big brush';
  static String fromThemCaption(String relative) => 'from them · $relative';
  static String youSentCaption(String relative) => 'you sent · $relative';

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
      "we'll fill this in the moment they're around ♡";
  static const notificationDevicesPhone = '📱 phone';
  static const notificationDevicesDesktop = '🖥 computer';
  static const notificationDevicesBoth = '📱 phone · 🖥 computer';
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
  static const superpowerServiceRunning = 'running ♡';
  static const superpowerServiceStopped = 'off';
  static const superpowerServiceStart = 'start';
  static const superpowerServiceStop = 'stop';
  static const superpowersOpenSettingsFailed =
      "couldn't find that settings screen (・_・;) — your phone may hide it.";

  static const superpowerUsageAccessTitle = 'share what app you\'re in';
  static const superpowerUsageAccessBody =
      "android calls this \"usage access\". it lets Kehai see which app is "
      "in front right now, so your person's card can say something like "
      "\"coding ⌨\" or \"gaming 🎮\" instead of just \"on their phone\". we "
      "only ever read the current app's name — never anything on screen — "
      "and you can revoke it in settings any second.";

  static const shareFocusedAppTitle = 'share what app you\'re focused on';
  static const shareFocusedAppBody =
      "tells them what app you're focused on, like \"coding ⌨\" or "
      "\"gaming 🎮\" — off means we never look. it sits one rung below "
      "now-playing, so if you're mid-song it says that instead.";
  static const shareFocusedAppOn = 'sharing ✓';
  static const shareFocusedAppOff = 'off';
  static const shareFocusedAppTurnOn = 'turn on';
  static const shareFocusedAppTurnOff = 'turn off';

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
}
