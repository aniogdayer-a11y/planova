import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../widgets/planova_brand.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';

class AuthScreen extends StatefulWidget {
  final bool startWithReset;
  final String initialEmail;
  const AuthScreen({
    super.key,
    this.startWithReset = false,
    this.initialEmail = '',
  });
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController(),
      _name = TextEditingController(),
      _code = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _createAccount = false, _reset = false, _obscure = true;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _reset = widget.startWithReset;
    _email.text = widget.initialEmail;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in [_email, _name, _code, _password, _confirm]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _mode(AuthProvider auth, {bool create = false, bool reset = false}) {
    auth.changeEmail();
    _code.clear();
    _password.clear();
    _confirm.clear();
    setState(() {
      _createAccount = create;
      _reset = reset;
    });
  }

  Future<void> _submit(AuthProvider auth) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    if (auth.challengeId != null) {
      if (_reset) {
        final success = await auth.resetPassword(_code.text, _password.text);
        if (success && mounted) {
          setState(() {
            _reset = false;
            _createAccount = false;
          });
          _password.clear();
          _confirm.clear();
          _code.clear();
        }
      } else {
        await auth.verify(_code.text);
      }
    } else {
      await auth.requestCode(
        email: _email.text,
        name: _name.text,
        password: _password.text,
        createAccount: _createAccount,
        resetPassword: _reset,
      );
    }
  }

  Widget _passwordInput({bool confirm = false, bool newPassword = false}) =>
      TextFormField(
        key: ValueKey(confirm ? 'auth-confirm-password' : 'auth-password'),
        controller: confirm ? _confirm : _password,
        obscureText: _obscure,
        autocorrect: false,
        enableSuggestions: false,
        maxLength: 128,
        autofillHints: [
          newPassword ? AutofillHints.newPassword : AutofillHints.password,
        ],
        decoration: InputDecoration(
          labelText: confirm
              ? 'Confirm password'
              : newPassword
              ? 'New password'
              : 'Password',
          counterText: '',
          helperText: !confirm && newPassword
              ? 'At least 12 characters.'
              : null,
          suffixIcon: !confirm
              ? IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                )
              : null,
        ),
        validator: (value) {
          if (confirm) {
            return value == _password.text ? null : 'Passwords do not match.';
          }
          if (value == null || value.isEmpty) return 'Enter your password.';
          if (newPassword && value.length < 12) {
            return 'Use at least 12 characters.';
          }
          return null;
        },
        onFieldSubmitted: (_) => _submit(context.read<AuthProvider>()),
      );
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final verify = auth.challengeId != null;
    final wait = auth.resendAt == null
        ? 0
        : auth.resendAt!.difference(DateTime.now()).inSeconds.clamp(0, 60);
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: Card(
        color: const Color(0xFFFAF8EF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: EdgeInsets.all(wide ? 36 : 24),
          child: AutofillGroup(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    verify
                        ? _reset
                              ? 'Reset your password'
                              : 'Check your email'
                        : _reset
                        ? 'Forgot password'
                        : _createAccount
                        ? 'Create your account'
                        : 'Welcome back',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: wide ? 36 : 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (verify || _reset) ...[
                    const SizedBox(height: 12),
                    Text(
                      verify
                          ? 'Enter the code sent to ${_email.text.trim()}.'
                          : 'Enter your email for a reset code.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 36),
                  if (verify) ...[
                    TextFormField(
                      key: const ValueKey('auth-code'),
                      controller: _code,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Verification code',
                        hintText: '000000',
                      ),
                      validator: (value) =>
                          RegExp(r'^\d{6}$').hasMatch(value ?? '')
                          ? null
                          : 'Enter the six-digit code.',
                      onFieldSubmitted: (_) => _submit(auth),
                    ),
                    if (_reset) ...[
                      const SizedBox(height: 16),
                      _passwordInput(newPassword: true),
                      const SizedBox(height: 16),
                      _passwordInput(confirm: true, newPassword: true),
                    ],
                  ] else ...[
                    if (_createAccount) ...[
                      TextFormField(
                        key: const ValueKey('auth-name'),
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        maxLength: 60,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          counterText: '',
                        ),
                        validator: (value) => (value?.trim().length ?? 0) < 2
                            ? 'Enter your name.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      key: const ValueKey('auth-email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                      ),
                      validator: (value) =>
                          RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch(value?.trim() ?? '')
                          ? null
                          : 'Enter a valid email address.',
                    ),
                    if (!_reset) ...[
                      const SizedBox(height: 16),
                      _passwordInput(newPassword: _createAccount),
                      if (_createAccount) ...[
                        const SizedBox(height: 16),
                        _passwordInput(confirm: true, newPassword: true),
                      ] else
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: auth.busy
                                ? null
                                : () => _mode(auth, reset: true),
                            child: const Text('Forgot password?'),
                          ),
                        ),
                    ],
                  ],
                  if (auth.error != null || auth.message != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        auth.error ?? auth.message!,
                        style: TextStyle(
                          color: auth.error != null
                              ? Theme.of(context).colorScheme.error
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: auth.busy ? null : () => _submit(auth),
                    child: Text(
                      auth.busy
                          ? 'Please wait...'
                          : verify
                          ? _reset
                                ? 'Reset password'
                                : 'Verify and sign in'
                          : _reset
                          ? 'Send reset code'
                          : _createAccount
                          ? 'Create account'
                          : 'Sign in',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (verify) ...[
                    TextButton(
                      onPressed: auth.busy || wait > 0
                          ? null
                          : () {
                              _code.clear();
                              auth.resend();
                            },
                      child: Text(
                        wait > 0 ? 'Resend code in ${wait}s' : 'Resend code',
                      ),
                    ),
                    TextButton(
                      onPressed: auth.busy
                          ? null
                          : () {
                              auth.changeEmail();
                              _code.clear();
                              _password.clear();
                              _confirm.clear();
                            },
                      child: const Text('Use a different email'),
                    ),
                  ] else
                    TextButton(
                      onPressed: auth.busy
                          ? null
                          : () {
                              if (widget.startWithReset) {
                                auth.changeEmail();
                                Navigator.pop(context);
                              } else {
                                _mode(auth, create: !_createAccount && !_reset);
                              }
                            },
                      child: Text(
                        widget.startWithReset
                            ? 'Cancel'
                            : _reset || _createAccount
                            ? 'Back to sign in'
                            : 'Create account',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: const Color(0xFF272A28),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.all(wide ? 40 : 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - (wide ? 80 : 40)).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: PlanovaBrand(inverse: true, large: true),
                      ),
                      const SizedBox(height: 36),
                      form,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
