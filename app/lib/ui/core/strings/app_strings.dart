/// Centralized user-facing copy. Keeping every string here (instead of
/// inline in widgets) means swapping to real l10n (ARB files, per
/// design-language.md "Polish + English localization from day one") later
/// is a mechanical move, not a rewrite. Voice: warm, plain, sentence case,
/// kaomoji accents, honest errors — see kb/design-language.md.
class AppStrings {
  const AppStrings._();

  // App
  static const appName = 'our desktop';

  // Onboarding — server step
  static const serverStepTitle = 'find your server';
  static const serverStepBody =
      "enter the address of your home server (or its Tailscale name). "
      "we'll just say hi first — nothing is sent until you log in.";
  static const serverUrlLabel = 'server address';
  static const serverUrlHint = 'https://100.x.x.x:8090 or https://couples.tail...ts.net';
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
  static const waitingBody = 'send them your invite code and they can join any time.';
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

  // Home — countdowns
  static const countdownsTitle = 'countdowns';
  static const countdownsEmpty =
      "nothing counted down yet… add something to look forward to! (￣ω￣)";
  static const addCountdown = 'add';
  static const countdownToday = 'today!! ✧';
  static String countdownInDays(int days) => 'in $days ${days == 1 ? 'day' : 'days'}';
  static String countdownDaysAgo(int days) => '$days ${days == 1 ? 'day' : 'days'} ago';
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
  static String togetherDays(int days) => 'together $days ${days == 1 ? 'day' : 'days'} ♡';
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

  // Generic
  static const loading = 'one sec… (｡•ᴗ•｡)';
  static const genericError = "something went sideways (；一_一) — try again?";
  static const retry = 'try again';
  static const cancel = 'cancel';
}
