import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../database/business_preferences.dart';

/// 应用锁：启动 / 回前台时要求输入数字 PIN 才能进入聊天；同时支持由 AI
/// 通过本地工具主动锁定（可指定时长，到期自动解锁）或解除锁定。
///
/// 纯 Dart 逻辑 + 持久化，不直接依赖 widget 树，便于单测。PIN 只存 SHA-256
/// 哈希（带固定盐），不落明文。生物识别（指纹/面容）作为后续接口预留。
class AppLockController extends ChangeNotifier {
  AppLockController(this._prefs);

  final BusinessPreferences _prefs;

  static const String _kEnabled = 'app_lock_enabled_v1';
  static const String _kPinHash = 'app_lock_pin_hash_v1';
  static const String _kLockOnResume = 'app_lock_lock_on_resume_v1';
  static const String _kAiLockUntil = 'app_lock_ai_until_v1';
  static const String _salt = 'kelivo_app_lock_v1::';

  bool _enabled = false;
  bool _hasPin = false;
  bool _lockOnResume = true;

  bool _aiLocked = false;
  DateTime? _aiLockUntil;
  Timer? _aiTimer;

  bool get enabled => _enabled;
  bool get hasPin => _hasPin;
  bool get lockOnResume => _lockOnResume;

  /// AI 主动锁定中（且尚未到期）。
  bool get aiLockActive =>
      _aiLocked &&
      (_aiLockUntil == null || DateTime.now().isBefore(_aiLockUntil!));

  /// AI 定时解锁时刻；`null` 表示持续锁定到主动解锁为止。
  DateTime? get aiLockUntil => _aiLockUntil;

  Future<void> load() async {
    await _prefs.load();
    _enabled = _prefs.getBool(_kEnabled) ?? false;
    _hasPin = (_prefs.getString(_kPinHash) ?? '').isNotEmpty;
    _lockOnResume = _prefs.getBool(_kLockOnResume) ?? true;

    final raw = _prefs.getString(_kAiLockUntil);
    final until = raw == null ? null : DateTime.tryParse(raw);
    if (until != null && DateTime.now().isBefore(until)) {
      _aiLocked = true;
      _aiLockUntil = until;
      _scheduleAutoUnlock(until);
    } else {
      _aiLocked = false;
      _aiLockUntil = null;
      if (raw != null) await _prefs.remove(_kAiLockUntil);
    }
    notifyListeners();
  }

  String _hash(String pin) =>
      sha256.convert(utf8.encode(_salt + pin)).toString();

  bool verifyPin(String pin) =>
      pin.isNotEmpty && _hash(pin) == (_prefs.getString(_kPinHash) ?? '');

  Future<void> setPin(String pin) async {
    await _prefs.setString(_kPinHash, _hash(pin));
    _hasPin = true;
    notifyListeners();
  }

  Future<void> clearPin() async {
    _aiTimer?.cancel();
    _aiTimer = null;
    _aiLocked = false;
    _aiLockUntil = null;
    await _prefs.remove(_kAiLockUntil);
    await _prefs.remove(_kPinHash);
    _hasPin = false;
    _enabled = false;
    await _prefs.setBool(_kEnabled, false);
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    // 没有 PIN 时不允许开启；先在设置页设置密码。
    if (value && !_hasPin) return;
    _enabled = value;
    await _prefs.setBool(_kEnabled, value);
    notifyListeners();
  }

  Future<void> setLockOnResume(bool value) async {
    _lockOnResume = value;
    await _prefs.setBool(_kLockOnResume, value);
    notifyListeners();
  }

  /// AI 锁定应用。[duration] 为空＝持续锁定，直到 AI 或用户解锁；
  /// 有值则到点自动解除。
  Future<void> lockFor({Duration? duration}) async {
    _aiTimer?.cancel();
    _aiLocked = true;
    _aiLockUntil = duration == null ? null : DateTime.now().add(duration);
    if (_aiLockUntil != null) {
      await _prefs.setString(_kAiLockUntil, _aiLockUntil!.toIso8601String());
      _scheduleAutoUnlock(_aiLockUntil!);
    } else {
      await _prefs.remove(_kAiLockUntil);
    }
    notifyListeners();
  }

  /// AI（或用户通过 PIN 解锁后）解除应用锁定。
  Future<void> unlock() async {
    _aiTimer?.cancel();
    _aiTimer = null;
    _aiLocked = false;
    _aiLockUntil = null;
    await _prefs.remove(_kAiLockUntil);
    notifyListeners();
  }

  void _scheduleAutoUnlock(DateTime until) {
    _aiTimer?.cancel();
    final delay = until.difference(DateTime.now());
    if (delay.inMilliseconds <= 0) {
      unawaited(unlock());
      return;
    }
    _aiTimer = Timer(delay, () => unawaited(unlock()));
  }

  @override
  void dispose() {
    _aiTimer?.cancel();
    _aiTimer = null;
    super.dispose();
  }
}
