import 'package:flutter/foundation.dart';

/// 模拟来电的阶段：响铃中 → 通话中 → 已结束。
enum CallPhase { ringing, active, ended }

/// 一通模拟来电的会话信息。只在 App 内模拟，不接运营商电话。
@immutable
final class CallSession {
  const CallSession({
    required this.conversationId,
    required this.assistantId,
    required this.assistantName,
    required this.avatar,
    required this.startedAt,
    required this.phase,
    this.openingLine,
    this.answeredAt,
  });

  final String conversationId;
  final String assistantId;
  final String assistantName;
  final String? avatar;

  /// 响铃（拉起来电）时刻。
  final DateTime startedAt;
  final CallPhase phase;

  /// 接通（进入通话中）时刻；未接通为 `null`。通话时长从这里算起，
  /// 不包含响铃等待时间。
  final DateTime? answeredAt;

  /// 接通后要先念出来的开场白；为空时由页面用通用模板兜底。
  final String? openingLine;

  CallSession copyWith({
    CallPhase? phase,
    String? openingLine,
    DateTime? answeredAt,
  }) {
    return CallSession(
      conversationId: conversationId,
      assistantId: assistantId,
      assistantName: assistantName,
      avatar: avatar,
      startedAt: startedAt,
      phase: phase ?? this.phase,
      openingLine: openingLine ?? this.openingLine,
      answeredAt: answeredAt ?? this.answeredAt,
    );
  }
}

/// 模拟来电的状态机。页面监听 [session] 渲染响铃 / 通话界面；
/// 空闲触发、定时任务等链路通过 [start] 拉起一通来电。
final class IncomingCallService {
  IncomingCallService._();

  /// 全局单例。
  static final IncomingCallService instance = IncomingCallService._();

  /// 当前来电会话；`null` 表示没有进行中的通话。
  final ValueNotifier<CallSession?> session = ValueNotifier(null);

  /// 接听后由上层注入：按会话上下文生成通话第一句并回填到会话。
  void Function(CallSession session)? onAnswered;

  /// 挂断回调：携带本次会话与实际通话时长（未接通为 `null`），由上层
  /// （控制器）写聊天记录等。
  void Function(CallSession session, Duration? duration)? onHangUp;

  /// 最近一通通话的实际时长；未接通或尚未挂断为 `null`。
  Duration? lastCallDuration;

  bool get hasActiveCall =>
      session.value != null && session.value!.phase != CallPhase.ended;

  /// 拉起一通响铃中的来电。
  void start({
    required String conversationId,
    required String assistantId,
    required String assistantName,
    String? avatar,
    String? openingLine,
  }) {
    lastCallDuration = null;
    session.value = CallSession(
      conversationId: conversationId,
      assistantId: assistantId,
      assistantName: assistantName,
      avatar: avatar,
      startedAt: DateTime.now(),
      phase: CallPhase.ringing,
      openingLine: openingLine,
    );
  }

  /// 接听：进入通话中，记录接通时刻，并通知上层按上下文生成通话第一句。
  void answer() {
    final current = session.value;
    if (current == null || current.phase != CallPhase.ringing) return;
    final active = current.copyWith(
      phase: CallPhase.active,
      answeredAt: DateTime.now(),
    );
    session.value = active;
    onAnswered?.call(active);
  }

  /// 回填生成好的通话第一句，供通话页 TTS 播报。
  void setOpeningLine(String line) {
    final current = session.value;
    if (current == null) return;
    session.value = current.copyWith(openingLine: line.trim());
  }

  /// 挂断：计算实际通话时长（仅接通后计入），通知上层后清空会话。
  void hangUp() {
    final current = session.value;
    Duration? duration;
    if (current != null && current.answeredAt != null) {
      duration = DateTime.now().difference(current.answeredAt!);
      // 不足一秒按 0 处理，避免出现 00:00 之外的异常负值。
      if (duration.isNegative) duration = Duration.zero;
    }
    lastCallDuration = duration;
    onHangUp?.call(current!, duration);
    session.value = null;
  }
}
