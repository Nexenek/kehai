import 'package:flutter/material.dart';

import '../../../../app_controller.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/retro_window.dart';
import '../view_models/auth_view_model.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late final AuthViewModel _viewModel;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final controller = AppScope.of(context, listen: false);
    _viewModel = AuthViewModel(controller.authRepository!);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = AppScope.of(context, listen: false);
    final ok = await _viewModel.submit(
      email: _emailController.text,
      password: _passwordController.text,
      name: _nameController.text,
    );
    if (ok) controller.onAuthenticated();
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
                  final isRegister = _viewModel.isRegisterMode;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(AppStrings.authStepTitle, style: AppTextStyles.heading),
                      const SizedBox(height: 8),
                      Text(
                        isRegister ? AppStrings.authStepBodyRegister : AppStrings.authStepBodyLogin,
                        style: AppTextStyles.body2,
                      ),
                      const SizedBox(height: 16),
                      if (isRegister) ...[
                        Text(AppStrings.nameLabel, style: AppTextStyles.caption),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _nameController,
                          style: AppTextStyles.body1,
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(AppStrings.emailLabel, style: AppTextStyles.caption),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: AppTextStyles.body1,
                      ),
                      const SizedBox(height: 12),
                      Text(AppStrings.passwordLabel, style: AppTextStyles.caption),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        style: AppTextStyles.body1,
                      ),
                      const SizedBox(height: 14),
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
                          PixelButton(
                            primary: true,
                            label: _viewModel.isSubmitting
                                ? AppStrings.loading
                                : (isRegister ? AppStrings.registerButton : AppStrings.loginButton),
                            onPressed: _viewModel.isSubmitting ? null : _submit,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _viewModel.toggleMode,
                        child: Text(
                          isRegister ? AppStrings.switchToLogin : AppStrings.switchToRegister,
                          style: AppTextStyles.caption.copyWith(
                            color: colors.accent,
                            decoration: TextDecoration.underline,
                          ),
                        ),
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
