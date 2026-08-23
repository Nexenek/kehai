import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app_controller.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/bevel_box.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/retro_window.dart';
import '../view_models/couple_setup_view_model.dart';

class CoupleSetupScreen extends StatefulWidget {
  const CoupleSetupScreen({super.key});

  @override
  State<CoupleSetupScreen> createState() => _CoupleSetupScreenState();
}

class _CoupleSetupScreenState extends State<CoupleSetupScreen> {
  late final CoupleSetupViewModel _viewModel;
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _justCopied = false;

  @override
  void initState() {
    super.initState();
    final controller = AppScope.of(context, listen: false);
    _viewModel = CoupleSetupViewModel(
      controller.coupleRepository!,
      controller.prefs,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: RetroWindow(
              title: AppStrings.appName,
              width: 460,
              child: ListenableBuilder(
                listenable: _viewModel,
                builder: (context, _) => _buildBody(context, colors),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppColors colors) {
    if (_viewModel.createdCouple != null) {
      return _InviteCodeReveal(
        code: _viewModel.createdCouple!.inviteCode,
        copied: _justCopied,
        onCopy: () async {
          await Clipboard.setData(
            ClipboardData(text: _viewModel.createdCouple!.inviteCode),
          );
          setState(() => _justCopied = true);
        },
        onContinue: () => AppScope.of(context, listen: false).onCoupleReady(),
      );
    }

    switch (_viewModel.mode) {
      case CoupleSetupMode.choose:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppStrings.coupleStepTitle, style: AppTextStyles.heading),
            const SizedBox(height: 8),
            Text(AppStrings.coupleStepBody, style: AppTextStyles.body2),
            const SizedBox(height: 18),
            PixelButton(
              primary: true,
              label: AppStrings.createCoupleButton,
              onPressed: _viewModel.showCreate,
            ),
            const SizedBox(height: 10),
            PixelButton(
              label: AppStrings.joinCoupleButton,
              onPressed: _viewModel.showJoin,
            ),
          ],
        );
      case CoupleSetupMode.create:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppStrings.coupleNameLabel, style: AppTextStyles.heading),
            const SizedBox(height: 10),
            TextField(
              controller: _nameController,
              style: AppTextStyles.body1,
              decoration: const InputDecoration(
                hintText: AppStrings.coupleNameHint,
              ),
            ),
            const SizedBox(height: 12),
            if (_viewModel.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _viewModel.errorMessage!,
                  style: AppTextStyles.body2.copyWith(color: colors.warn),
                ),
              ),
            Row(
              children: [
                PixelButton(label: AppStrings.back, onPressed: _viewModel.back),
                const SizedBox(width: 10),
                PixelButton(
                  primary: true,
                  label: _viewModel.isSubmitting
                      ? AppStrings.loading
                      : AppStrings.createButton,
                  onPressed: _viewModel.isSubmitting
                      ? null
                      : () => _viewModel.create(_nameController.text),
                ),
              ],
            ),
          ],
        );
      case CoupleSetupMode.join:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppStrings.enterCodeLabel, style: AppTextStyles.heading),
            const SizedBox(height: 10),
            TextField(
              controller: _codeController,
              style: AppTextStyles.body1,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: AppStrings.enterCodeHint,
              ),
            ),
            const SizedBox(height: 12),
            if (_viewModel.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _viewModel.errorMessage!,
                  style: AppTextStyles.body2.copyWith(color: colors.warn),
                ),
              ),
            Row(
              children: [
                PixelButton(label: AppStrings.back, onPressed: _viewModel.back),
                const SizedBox(width: 10),
                PixelButton(
                  primary: true,
                  label: _viewModel.isSubmitting
                      ? AppStrings.loading
                      : AppStrings.joinButton,
                  onPressed: _viewModel.isSubmitting
                      ? null
                      : () async {
                          final ok = await _viewModel.join(
                            _codeController.text,
                          );
                          if (ok && context.mounted) {
                            AppScope.of(context, listen: false).onCoupleReady();
                          }
                        },
                ),
              ],
            ),
          ],
        );
    }
  }
}

class _InviteCodeReveal extends StatelessWidget {
  const _InviteCodeReveal({
    required this.code,
    required this.copied,
    required this.onCopy,
    required this.onContinue,
  });

  final String code;
  final bool copied;
  final VoidCallback onCopy;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '(｡♥‿♥｡)',
          style: AppTextStyles.kaomojiMedium.copyWith(color: colors.accent),
        ),
        const SizedBox(height: 12),
        Text(AppStrings.inviteCodeLabel, style: AppTextStyles.caption),
        const SizedBox(height: 6),
        BevelBox(
          color: colors.chrome,
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: Text(
              code,
              style: AppTextStyles.heading.copyWith(
                fontSize: 32,
                letterSpacing: 6,
                color: colors.ink,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          AppStrings.inviteCodeExplainer,
          style: AppTextStyles.body2,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PixelButton(
              label: copied ? AppStrings.codeCopied : AppStrings.copyCode,
              onPressed: onCopy,
            ),
            const SizedBox(width: 10),
            PixelButton(
              primary: true,
              label: AppStrings.continueLabel,
              onPressed: onContinue,
            ),
          ],
        ),
      ],
    );
  }
}
