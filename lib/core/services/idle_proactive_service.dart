import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/idle_proactive_settings.dart';

/// 空闲超时主动触发服务。
///
/// 职责边界：
/// - 持久化配置与最后互动时间；
/// - 周期判断是否超过空闲阈值；
/// - 按概率把一次超时分流为「主动发消息」或「模拟来电」。
///
/// 不直接依赖聊天/角色 provider：目标会话由上层通过 [pickTarget] 注入，
/// 真正执行发言 / 来电由 [onTrigger] 回调给上层完成，避免循环依赖。
final class IdleProactiveService {
  IdleProactiveService._();

  /// 全局单例。
  static final IdleProactiveService instance = IdleProactiveService._();

  static const String _cfgKey = 'idle_proactive_cfg_v1';
  static const String _lastActiveKey = 'idle_proactive_last_active_v1';

  SharedPreferences? _prefs;
  Timer? _timer;
  final Random _random = Random();
  IdleProactiveSettings _settings = const IdleProactiveSettings();

  /// 返回当前最久未互动、允许被主动触发的会话；没有则返回 `null`。
  /// 由上层（持有 ChatService / AssistantProvider）注入实现，带回该会话
  /// 的最后互动时间，作为空闲判定基准。
  IdleProactiveTarget? Function()? pickTarget;

  /// 触发回调：上层据此执行主动发言或拉起模拟来电。
  void Function(String conversationId, IdleProactiveAction action)? onTrigger;

  IdleProactiveSettings get settings => _settings;

  /// 初始化：读取已存配置并启动周期检查。可重复调用。
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_cfgKey);
    if (raw != null) {
      try {
        _settings = IdleProactiveSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        _settings = const IdleProactiveSettings();
      }
    }
    _startTimer();
  }

  Future<void> updateSettings(IdleProactiveSettings settings) async {
    _settings = settings;
    await _prefs?.setString(_cfgKey, jsonEncode(settings.toJson()));
  }

  /// 记录一次用户互动（发消息、打开会话等），重置空闲计时。
  Future<void> markActive() async {
    await _prefs?.setInt(_lastActiveKey, DateTime.now().microsecondsSinceEpoch);
  }

  /// 最近一次互动时间；从未互动时为 `null`。
  DateTime? get lastActiveAt {
    final value = _prefs?.getInt(_lastActiveKey);
    if (value == null) return null;
    return DateTime.fromMicrosecondsSinceEpoch(value);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_tick()),
    );
  }

  Future<void> _tick() async {
    if (!_settings.enabled || onTrigger == null) return;
    final target = pickTarget?.call();
    if (target == null || target.conversationId.isEmpty) return;
    final action = resolveAction(
      settings: _settings,
      now: DateTime.now(),
      lastActiveAt: target.lastActiveAt,
      idleDuration: _settings.idleDuration,
      random0to99: _random.nextInt(100),
    );
    if (action == IdleProactiveAction.none) return;
    onTrigger!(target.conversationId, action);
  }

  /// 纯分流逻辑：给定配置、当前时间、最后互动时间、空闲阈值和一次随机数，
  /// 决定本次超时应触发哪种行为。便于单元测试。
  static IdleProactiveAction resolveAction({
    required IdleProactiveSettings settings,
    required DateTime now,
    required DateTime? lastActiveAt,
    required Duration idleDuration,
    required int random0to99,
  }) {
    if (!settings.enabled) return IdleProactiveAction.none;
    final last = lastActiveAt ?? now;
    if (now.difference(last) < idleDuration) return IdleProactiveAction.none;

    final callHit =
        settings.allowCall && random0to99 < settings.normalizedCallProbability;
    if (callHit) return IdleProactiveAction.call;
    if (settings.allowMessage) return IdleProactiveAction.message;
    if (settings.allowCall) return IdleProactiveAction.call;
    return IdleProactiveAction.none;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
