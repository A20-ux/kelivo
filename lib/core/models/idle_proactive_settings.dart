/// 空闲超时主动触发配置。
///
/// 与固定时间点的定时任务不同：这里以「用户多久没和角色互动」为条件，
/// 超过 [idleMinutes] 没有互动就触发一次主动行为；一旦用户发消息或打开
/// 会话，计时立刻重置。
final class IdleProactiveSettings {
  const IdleProactiveSettings({
    this.enabled = false,
    this.idleMinutes = 30,
    this.callProbability = 30,
    this.allowMessage = true,
    this.allowCall = true,
  });

  /// 总开关：是否启用空闲主动触发。
  final bool enabled;

  /// 空闲多久（分钟）后触发。
  final int idleMinutes;

  /// 触发时改打模拟来电的概率，0–100；其余概率走主动发消息。
  final int callProbability;

  /// 允许空闲时自动发消息。
  final bool allowMessage;

  /// 允许空闲时主动打模拟来电。
  final bool allowCall;

  /// 来电概率收敛到 0–100。
  int get normalizedCallProbability => callProbability.clamp(0, 100);

  Duration get idleDuration => Duration(minutes: idleMinutes.clamp(1, 1440));

  IdleProactiveSettings copyWith({
    bool? enabled,
    int? idleMinutes,
    int? callProbability,
    bool? allowMessage,
    bool? allowCall,
  }) {
    return IdleProactiveSettings(
      enabled: enabled ?? this.enabled,
      idleMinutes: idleMinutes ?? this.idleMinutes,
      callProbability: callProbability ?? this.callProbability,
      allowMessage: allowMessage ?? this.allowMessage,
      allowCall: allowCall ?? this.allowCall,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'idleMinutes': idleMinutes,
    'callProbability': normalizedCallProbability,
    'allowMessage': allowMessage,
    'allowCall': allowCall,
  };

  factory IdleProactiveSettings.fromJson(Map<String, dynamic> json) {
    return IdleProactiveSettings(
      enabled: json['enabled'] == true,
      idleMinutes: (json['idleMinutes'] as num?)?.toInt() ?? 30,
      callProbability: (json['callProbability'] as num?)?.toInt() ?? 30,
      allowMessage: json['allowMessage'] != false,
      allowCall: json['allowCall'] != false,
    );
  }
}

/// 空闲超时后决定的主动行为。
enum IdleProactiveAction { none, message, call }

/// 被挑中作为主动触发目标的会话及其最后互动时间。
final class IdleProactiveTarget {
  const IdleProactiveTarget({
    required this.conversationId,
    required this.lastActiveAt,
  });

  final String conversationId;
  final DateTime lastActiveAt;
}
