import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/services/app_lock_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/section_card.dart';

/// 应用锁设置：开关、回前台锁定、设置 / 修改 / 删除数字 PIN。
class AppLockSettingsPage extends StatefulWidget {
  const AppLockSettingsPage({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AppLockSettingsPage()));
  }

  @override
  State<AppLockSettingsPage> createState() => _AppLockSettingsPageState();
}

class _AppLockSettingsPageState extends State<AppLockSettingsPage> {
  Future<void> _showPinSheet({required AppLockController lock}) async {
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        final l10n = AppLocalizations.of(sheetCtx)!;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lock.hasPin ? l10n.appLockChangePin : l10n.appLockSetPin,
                style: Theme.of(sheetCtx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              IosFormTextField(
                label: l10n.appLockSetPin,
                controller: pinCtrl,
                hintText: l10n.appLockPinHint,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 12),
              IosFormTextField(
                label: l10n.appLockPinConfirm,
                controller: confirmCtrl,
                hintText: l10n.appLockPinConfirm,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(sheetCtx).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                    child: Text(
                      MaterialLocalizations.of(sheetCtx).cancelButtonLabel,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final pin = pinCtrl.text.trim();
                      final confirm = confirmCtrl.text.trim();
                      if (pin.length < 4 || pin.length > 8) {
                        setState(() => error = l10n.appLockPinHint);
                        return;
                      }
                      if (pin != confirm) {
                        setState(() => error = l10n.appLockPinMismatch);
                        return;
                      }
                      await lock.setPin(pin);
                      if (!sheetCtx.mounted) return;
                      Navigator.of(sheetCtx).pop();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.appLockSaved)),
                      );
                    },
                    child: Text(
                      MaterialLocalizations.of(sheetCtx).okButtonLabel,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    pinCtrl.dispose();
    confirmCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lock = context.watch<AppLockController>();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: Text(l10n.appLockTitle),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionCard(
                children: [
                  IosNavRow(
                    icon: Icons.lock_outline,
                    label: l10n.appLockEnable,
                    subtitle: l10n.appLockEnableSubtitle,
                    trailing: IosSwitch(
                      value: lock.enabled,
                      onChanged: (v) async {
                        if (v && !lock.hasPin) {
                          await _showPinSheet(lock: lock);
                          return;
                        }
                        await lock.setEnabled(v);
                      },
                    ),
                  ),
                  const Divider(height: 1, indent: 12),
                  IosNavRow(
                    icon: Icons.lock_clock_outlined,
                    label: l10n.appLockLockOnResume,
                    trailing: IosSwitch(
                      value: lock.lockOnResume,
                      onChanged: lock.setLockOnResume,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SectionCard(
                children: [
                  IosNavRow(
                    icon: Icons.key_outlined,
                    label: lock.hasPin
                        ? l10n.appLockChangePin
                        : l10n.appLockSetPin,
                    onTap: () => _showPinSheet(lock: lock),
                  ),
                  if (lock.hasPin) ...[
                    const Divider(height: 1, indent: 12),
                    IosNavRow(
                      icon: Icons.lock_open_outlined,
                      label: l10n.appLockRemovePin,
                      destructive: true,
                      onTap: () async {
                        await lock.clearPin();
                        if (!mounted || !context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.appLockSaved)),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
