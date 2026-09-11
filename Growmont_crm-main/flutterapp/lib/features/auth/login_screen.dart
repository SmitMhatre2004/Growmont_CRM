import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../legal/legal_screen.dart';
import 'auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final error = await ref
        .read(authProvider.notifier)
        .login(_usernameController.text.trim(), _passwordController.text);

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _loading = false;
        _error = error;
      });
    } else {
      context.go('/dashboard');
    }
  }


  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 1024;

    return Scaffold(
      body: Row(
        children: [
          if (isWide)
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primaryGreen, AppColors.primaryBlue],
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.business,
                    size: AppSizing.iconHero,
                    color: Colors.white54,
                  ),
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Growmont',
                        style: AppTypography.pageTitle.copyWith(
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxxl),
                      Text(
                        'Login',
                        style: AppTypography.headingLarge.copyWith(
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        width: 80,
                        height: 3,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryGreen,
                          borderRadius: AppRadius.brXs,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxxl),
                      if (_error != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: AppColors.dangerSoft,
                            border: Border.all(
                              color: AppColors.danger.withValues(alpha: 0.3),
                            ),
                            borderRadius: AppRadius.brMd,
                          ),
                          child: Text(
                            _error!,
                            style: AppTypography.bodySecondary.copyWith(
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      TextField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          hintText: 'Username / Email',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: AppSpacing.xxxl),
                      SizedBox(
                        width: double.infinity,
                        height: AppSizing.controlLg,
                        child: FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: Text(_loading ? 'Logging in...' : 'Login'),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxxl),
                      const _LegalFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < kLegalDocuments.length; i++) ...[
          if (i > 0)
            Text(
              '  ·  ',
              style: AppTypography.caption.copyWith(
                color: AppColors.borderStrong,
              ),
            ),
          GestureDetector(
            // Opaque, and padded out to the minimum tap target: the label
            // itself is only ~14pt of text, which is far too small to hit
            // reliably on a phone.
            behavior: HitTestBehavior.opaque,
            onTap: () => showLegalDocuments(context, initialTab: i),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSizing.minTapTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.md,
                ),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    kLegalDocuments[i].label,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textMuted,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.border,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
