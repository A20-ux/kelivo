import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/services/app_lock_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_form_text_field.dart';

/// 包裹整棵应用树：开启应用锁后，未解锁前不暴露聊天内容；
/// 按设置在回到应用时重新锁定。
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      try {
        final lock = context.read<AppLockController>();
        if (lock.enabled && lock.lockOnResume) {
          if (mounted) setState(() => _unlocked = false);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockController>();
    // AI 主动锁定独立于 PIN 总开关；总开关开启时，未解锁的本次会话也上锁。
    final locked = lock.aiLockActive || (lock.enabled && !_unlocked);
    if (!locked) return widget.child;
    return _LockScreen(
      controller: lock,
      onUnlocked: () => setState(() => _unlocked = true),
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.controller, required this.onUnlocked});

  final AppLockController controller;
  final VoidCallback onUnlocked;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  final _pinCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    final pin = _pinCtrl.text.trim();
    if (widget.controller.verifyPin(pin)) {
      unawaited(widget.controller.unlock());
      widget.onUnlocked();
    } else {
      setState(() {
        _error = l10n.appLockPinWrong;
        _pinCtrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 44, color: cs.primary),
                const SizedBox(height: 16),
                Text(
                  l10n.appLockUnlock,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                IosFormTextField(
                  label: l10n.appLockSetPin,
                  controller: _pinCtrl,
                  hintText: l10n.appLockPinHint,
                  obscureText: true,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.error),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _submit,
                  child: Text(MaterialLocalizations.of(context).okButtonLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
