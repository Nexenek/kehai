import 'package:flutter/material.dart';

import '../../../../app_controller.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/retro_window.dart';
import '../view_models/server_setup_view_model.dart';

class ServerUrlScreen extends StatefulWidget {
  const ServerUrlScreen({super.key});

  @override
  State<ServerUrlScreen> createState() => _ServerUrlScreenState();
}

class _ServerUrlScreenState extends State<ServerUrlScreen> {
  late final ServerSetupViewModel _viewModel;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    final controller = AppScope.of(context, listen: false);
    _viewModel = ServerSetupViewModel(controller);
    // Whatever is already saved, shown. Landing here almost never means
    // "you've never had a server" — it means the address needs a look
    // (changing it from settings, or the rare boot that really couldn't
    // build a client) — and an empty field made people retype an address
    // the app was holding all along.
    final saved = controller.serverUrl;
    if (saved.isNotEmpty) {
      _controller.text = saved;
      _controller.selection = TextSelection.collapsed(offset: saved.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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
              width: 440,
              child: ListenableBuilder(
                listenable: _viewModel,
                builder: (context, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppStrings.serverStepTitle,
                        style: AppTextStyles.heading,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        AppStrings.serverStepBody,
                        style: AppTextStyles.body2.copyWith(color: colors.ink),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        AppStrings.serverUrlLabel,
                        style: AppTextStyles.caption,
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _controller,
                        keyboardType: TextInputType.url,
                        style: AppTextStyles.body1,
                        decoration: const InputDecoration(
                          hintText: AppStrings.serverUrlHint,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_viewModel.testSucceeded)
                        Text(
                          AppStrings.connectionOk,
                          style: AppTextStyles.body2.copyWith(
                            color: colors.mint,
                          ),
                        )
                      else if (_viewModel.errorMessage != null)
                        Text(
                          _viewModel.errorMessage!,
                          style: AppTextStyles.body2.copyWith(
                            color: colors.warn,
                          ),
                        ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          PixelButton(
                            label: _viewModel.isTesting
                                ? AppStrings.loading
                                : AppStrings.testConnection,
                            onPressed: _viewModel.isTesting
                                ? null
                                : () => _viewModel.testConnection(
                                    _controller.text,
                                  ),
                          ),
                          const SizedBox(width: 10),
                          PixelButton(
                            primary: true,
                            label: _viewModel.isSubmitting
                                ? AppStrings.loading
                                : AppStrings.continueLabel,
                            onPressed: _viewModel.isSubmitting
                                ? null
                                : () => _viewModel.confirmAndContinue(
                                    _controller.text,
                                  ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
