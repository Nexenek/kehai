import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/shared_file_repository.dart';
import 'package:couples_app/domain/models/shared_file.dart';

void main() {
  group('sharedFileFromRecord', () {
    test('maps every field', () {
      final record = RecordModel({
        'id': 'file1',
        'collectionId': 'shared_files_col',
        'collectionName': 'shared_files',
        'couple': 'couple1',
        'uploaded_by': 'user1',
        'file': 'vacation_ab12cd.zip',
        'label': 'vacation photos.zip',
        'created': '2026-08-23 12:34:56.000Z',
      });

      final file = sharedFileFromRecord(record);

      expect(file.id, 'file1');
      expect(file.coupleId, 'couple1');
      expect(file.uploadedBy, 'user1');
      expect(file.filename, 'vacation_ab12cd.zip');
      expect(file.label, 'vacation photos.zip');
      expect(file.displayLabel, 'vacation photos.zip');
      expect(file.created.toUtc(), DateTime.utc(2026, 8, 23, 12, 34, 56));
    });

    test('an empty label falls back to the raw filename for display', () {
      final record = RecordModel({
        'id': 'file2',
        'collectionId': 'shared_files_col',
        'collectionName': 'shared_files',
        'couple': 'couple1',
        'uploaded_by': 'user1',
        'file': 'notes_xy99.txt',
        'label': '',
        'created': '2026-08-23 12:34:56.000Z',
      });

      final file = sharedFileFromRecord(record);

      expect(file.label, '');
      expect(file.displayLabel, 'notes_xy99.txt');
      expect(file.extension, 'txt');
    });

    test('an unparsable created falls back to "now" rather than throwing', () {
      final record = RecordModel({
        'id': 'file3',
        'collectionId': 'shared_files_col',
        'collectionName': 'shared_files',
        'couple': 'couple1',
        'uploaded_by': 'user1',
        'file': 'notes.txt',
        'label': '',
        'created': 'not-a-date',
      });

      final before = DateTime.now();
      final file = sharedFileFromRecord(record);
      final after = DateTime.now();

      expect(
        file.created.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        file.created.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });
  });

  group('SharedFile.extension', () {
    SharedFile fileNamed(String filename) => SharedFile(
      id: 'f',
      coupleId: 'c',
      uploadedBy: 'u',
      filename: filename,
      label: '',
      created: DateTime(2026),
    );

    test('lowercases a normal extension', () {
      expect(fileNamed('Archive.ZIP').extension, 'zip');
    });

    test('is empty for a filename with no extension', () {
      expect(fileNamed('README').extension, '');
    });

    test('is empty for a dotfile with no real extension', () {
      expect(fileNamed('.gitignore').extension, '');
    });

    test('takes the last extension of a multi-dot filename', () {
      expect(fileNamed('archive.tar.gz').extension, 'gz');
    });

    test('is empty for a filename ending in a bare dot', () {
      expect(fileNamed('weird.').extension, '');
    });
  });

  group('sharedFileDownloadUrl', () {
    // Pure string-building against the file's id/filename plus a
    // caller-supplied token — no network call — same reasoning as
    // instant_repository_test.dart's use of a bare fake-base-URL client.
    final pb = PocketBase('https://example.invalid');

    test('builds an absolute, tokenized file URL', () {
      final file = SharedFile(
        id: 'file1',
        coupleId: 'couple1',
        uploadedBy: 'user1',
        filename: 'vacation_ab12cd.zip',
        label: 'vacation photos.zip',
        created: DateTime(2026),
      );

      final url = sharedFileDownloadUrl(pb, file, 'abc123token');

      expect(
        url,
        'https://example.invalid/api/files/shared_files/file1/vacation_ab12cd.zip?token=abc123token',
      );
    });
  });
}
