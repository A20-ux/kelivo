import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/database/app_database.dart';
import 'package:Kelivo/core/database/business_preferences.dart';
import 'package:Kelivo/core/database/business_repository.dart';
import 'package:Kelivo/core/services/app_lock_controller.dart';

void main() {
  late AppDatabase database;
  late BusinessPreferences prefs;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    prefs = BusinessPreferences(BusinessRepository(database));
    await prefs.load();
  });

  tearDown(() async {
    await database.close();
  });

  test('starts disabled without a PIN', () async {
    final lock = AppLockController(prefs);
    await lock.load();
    expect(lock.enabled, isFalse);
    expect(lock.hasPin, isFalse);
    expect(lock.lockOnResume, isTrue);
  });

  test('setPin stores a hash and verifies the PIN', () async {
    final lock = AppLockController(prefs);
    await lock.load();
    await lock.setPin('1234');
    expect(lock.hasPin, isTrue);
    expect(lock.verifyPin('1234'), isTrue);
    expect(lock.verifyPin('4321'), isFalse);
    expect(lock.verifyPin(''), isFalse);
  });

  test('cannot enable lock before a PIN is set', () async {
    final lock = AppLockController(prefs);
    await lock.load();
    await lock.setEnabled(true);
    expect(lock.enabled, isFalse);
  });

  test(
    'enables after a PIN is set and clears everything on clearPin',
    () async {
      final lock = AppLockController(prefs);
      await lock.load();
      await lock.setPin('2468');
      await lock.setEnabled(true);
      expect(lock.enabled, isTrue);

      await lock.clearPin();
      expect(lock.hasPin, isFalse);
      expect(lock.enabled, isFalse);
      expect(lock.verifyPin('2468'), isFalse);
    },
  );

  test('persists lock-on-resume preference', () async {
    final lock = AppLockController(prefs);
    await lock.load();
    await lock.setLockOnResume(false);
    expect(lock.lockOnResume, isFalse);

    final reloaded = AppLockController(prefs);
    await reloaded.load();
    expect(reloaded.lockOnResume, isFalse);
  });
}
