import 'dart:async';

import 'package:flutter/foundation.dart';

import 'call_ringer.dart';

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
  });

  final String conversationId;
  final String assistantId;
  final String assistantName;
  final String? avatar;
  final DateTime startedAt;
  final CallPhase phase;

  /// 接通后要先念出来的开场白；为空时由页面用通用模板兜底。
  final String? openingLine;

  CallSession copyWith({CallPhase? phase, String? openingLine}) {
    return CallSession(
      conversationId: conversationId,
      assistantId: assistantId,
      assistantName: assistantName,
      avatar: avatar,
      startedAt: startedAt,
      phase: phase ?? this.phase,
      openingLine: openingLine ?? this.openingLine,
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
    session.value = CallSession(
      conversationId: conversationId,
      assistantId: assistantId,
      assistantName: assistantName,
      avatar: avatar,
      startedAt: DateTime.now(),
      phase: CallPhase.ringing,
      openingLine: openingLine,
    );
    unawaited(CallRinger.instance.start());
  }

  /// 接听：进入通话中，停止响铃。
  void answer() {
    final current = session.value;
    if (current == null || current.phase != CallPhase.ringing) return;
    unawaited(CallRinger.instance.stop());
    session.value = current.copyWith(phase: CallPhase.active);
  }

  /// 挂断：停止响铃并清空会话。
  void hangUp() {
    unawaited(CallRinger.instance.stop());
    session.value = null;
  }
}
