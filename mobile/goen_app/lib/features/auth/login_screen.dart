import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/goen_rings_mark.dart';
import '../../core/goen_theme.dart';
import '../../core/providers.dart';

/// S-001 ログイン画面（F-001）
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController(text: 'dev@example.com');
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final error = await ref.read(authSessionProvider.notifier).login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _errorMessage = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: GoenColors.primary,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: Column(
                children: [
                  GoenRingsMark(size: 84, color: GoenColors.ivory, strokeWidthRatio: 0.18),
                  const SizedBox(height: 14),
                  Text(
                    'GOEN',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: GoenColors.ivory,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'たまたまの出会いに、意味を。',
                    style: theme.textTheme.bodyMedium?.copyWith(color: GoenColors.ivory.withValues(alpha: 0.85)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: GoenColors.paper,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'メールアドレス',
                                prefixIcon: Icon(Icons.mail_outline),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) => (v == null || v.isEmpty) ? 'メールアドレスを入力してください' : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              decoration: const InputDecoration(
                                labelText: 'パスワード',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              obscureText: true,
                              validator: (v) => (v == null || v.isEmpty) ? 'パスワードを入力してください' : null,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.error)),
                            ],
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _isSubmitting ? null : () => context.push('/forgot-password'),
                                child: const Text('パスワードをお忘れですか？'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: _isSubmitting ? null : _submit,
                              child: _isSubmitting
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('ログイン'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
