import 'package:flutter/material.dart';

import 'package:couples_app/ui/features/home/views/home_layout.dart';

/// Stand-in section contents for the layout/tray tests: the real sections
/// need a live PocketBase-backed view model each, and none of that is what
/// these tests are about — the composition is.
const stubPartnerText = 'partner-window';
const stubMoodText = 'mood-section';
const stubPetText = 'pet-section';
const stubThumbKissText = 'thumbkiss-section';
const stubCountdownsText = 'countdowns-section';
const stubNotesText = 'notes-section';
const stubMapText = 'map-section';
const stubInstantsText = 'instants-section';
const stubBoardText = 'board-section';
const stubQuestionText = 'question-section';

/// Records what the tray asked for, so tests can assert on the doodle button
/// opening the canvas rather than a drawer.
class SectionTaps {
  int doodle = 0;
  int logOut = 0;
}

HomeSections stubSections({SectionTaps? taps, HomeSectionBuilder? mood}) {
  final recorded = taps ?? SectionTaps();
  Widget section(String text, VoidCallback? onClose) => TextButton(
    // Tapping the stub is "the section's window was closed" — it stands in
    // for the RetroWindow ♥ the real sections wire to onClose.
    onPressed: onClose,
    child: Text(text),
  );

  return HomeSections(
    partner: const Text(stubPartnerText),
    mood: mood ?? (context, onClose) => section(stubMoodText, onClose),
    pet: (context, onClose) => section(stubPetText, onClose),
    thumbkiss: (context, onClose) => section(stubThumbKissText, onClose),
    countdowns: (context, onClose) => section(stubCountdownsText, onClose),
    notes: (context, onClose) => section(stubNotesText, onClose),
    map: (context, onClose) => section(stubMapText, onClose),
    instants: (context, onClose) => section(stubInstantsText, onClose),
    board: (context, onClose) => section(stubBoardText, onClose),
    question: (context, onClose) => section(stubQuestionText, onClose),
    onOpenDoodle: () => recorded.doodle++,
    onLogOut: () => recorded.logOut++,
  );
}
