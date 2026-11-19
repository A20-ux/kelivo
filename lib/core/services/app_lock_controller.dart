import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../database/business_preferences.dart';

/// 应用锁：启动 / 回前台时要求输入数字 PIN 才能进入聊天。
///
/// 纯 Dart 逻辑 + 持久化，不直接依赖 widget 树，便于单测。PIN 只存 SHA-256
/// 哈希（带固定盐），不落明文。生物识别（指纹/面容）作为后续接口预留，
/// 当前版本先以数字 PIN 闭环。
class AppLockController extends ChangeNotifier {
  AppLockController(this._prefs);

  final BusinessPreferences _prefs;

  static const String _kEnabled = 'app_lock_enabled_v1';
  static const String _kPinHash = 'app_lock_pin_hash_v1';
  static const String _kLockOnResume = 'app_lock_lock_on_resume_v1';
  static const String _salt = 'kelivo_app_lock_v1::';

  bool _enabled = false;
  bool _hasPin = false;
  bool _lockOnResume = true;

  bool get enabled => _enabled;
  bool get hasPin => _hasPin;
  bool get lockOnResume => _lockOnResume;

  Future<void> load() async {
    await _prefs.load();
    _enabled = _prefs.getBool(_kEnabled) ?? false;
    _hasPin = (_prefs.getString(_kPinHash) ?? '').isNotEmpty;
    _lockOnResume = _prefs.getBool(_kLockOnResume) ?? true;
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
}
