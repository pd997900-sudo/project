import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/gradient_button.dart';
import '../../providers/auth_provider.dart';
import 'sign_in_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;
  final String? portalRole;
  const ForgotPasswordScreen({super.key, this.initialEmail, this.portalRole});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  int _step = 1; // 1: Email, 2: Verify Code, 3: New Password

  final _emailController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  Timer? _resendTimer;
  int _resendCooldown = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _emailController.text = widget.initialEmail!;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    for (var c in _otpControllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _resendCooldown = 30;
    });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendCooldown > 1) {
        setState(() {
          _resendCooldown--;
        });
      } else {
        setState(() {
          _resendCooldown = 0;
        });
        timer.cancel();
      }
    });
  }

  void _handleSendResetCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid registered email address.'),
            backgroundColor: AppTheme.emergencyRed,
          ),
        );
      }
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.sendPasswordResetLink(email);

    if (mounted) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        if (success) {
          _startResendTimer();
          setState(() {
            _step = 2;
          });
          messenger.showSnackBar(
            SnackBar(
              content: Text('Reset code sent to $email. Check your inbox!'),
              backgroundColor: AppTheme.successGreen,
              duration: const Duration(seconds: 4),
            ),
          );
        } else if (authProvider.errorMessage != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(authProvider.errorMessage!),
              backgroundColor: AppTheme.emergencyRed,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  void _handleVerifyCode() async {
    final code = _otpControllers.map((c) => c.text.trim()).join();
    if (code.length < 6) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter the full 6-digit reset code.'),
            backgroundColor: AppTheme.emergencyRed,
          ),
        );
      }
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final email = _emailController.text.trim();
    final success = await authProvider.verifyPasswordResetCode(
      email: email,
      code: code,
    );

    if (mounted) {
      if (success) {
        setState(() {
          _step = 3;
        });
      } else if (authProvider.errorMessage != null) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(authProvider.errorMessage!),
              backgroundColor: AppTheme.emergencyRed,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  void _handleResendCode() async {
    if (_resendCooldown > 0) return;
    final email = _emailController.text.trim();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final success = await authProvider.sendPasswordResetLink(email);

    if (mounted) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null) {
        if (success) {
          _startResendTimer();
          for (var c in _otpControllers) {
            c.clear();
          }
          messenger.showSnackBar(
            SnackBar(
              content: Text('New reset code sent to $email.'),
              backgroundColor: AppTheme.successGreen,
            ),
          );
        } else if (authProvider.errorMessage != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(authProvider.errorMessage!),
              backgroundColor: AppTheme.emergencyRed,
            ),
          );
        }
      }
    }
  }

  void _handleResetPassword() async {
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter both password fields.'),
            backgroundColor: AppTheme.emergencyRed,
          ),
        );
      }
      return;
    }

    if (newPassword != confirmPassword) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Passwords do not match.'),
            backgroundColor: AppTheme.emergencyRed,
          ),
        );
      }
      return;
    }

    if (newPassword.length < 6) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password must be at least 6 characters long.'),
            backgroundColor: AppTheme.emergencyRed,
          ),
        );
      }
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final email = _emailController.text.trim();

    final success = await authProvider.confirmPasswordReset(
      email: email,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );

    if (mounted) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (success) {
        if (messenger != null) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Password reset successful. Please sign in.'),
              backgroundColor: AppTheme.successGreen,
              duration: Duration(seconds: 4),
            ),
          );
        }

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => SignInScreen(
              portalRole: widget.portalRole ?? authProvider.selectedRole,
              initialEmail: email,
              initialPassword: newPassword,
            ),
          ),
          (route) => false,
        );
      } else if (authProvider.errorMessage != null) {
        if (messenger != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(authProvider.errorMessage!),
              backgroundColor: AppTheme.emergencyRed,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      body: Container(
        decoration: AppTheme.gradientBackgroundDecoration,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                IconButton(
                  onPressed: () {
                    if (_step > 1) {
                      setState(() {
                        _step--;
                      });
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                ),
                const SizedBox(height: 10),

                // Dynamic Header based on Step
                Text(
                  _step == 1
                      ? 'Forgot Password'
                      : _step == 2
                          ? 'Verify Reset Code'
                          : 'Create New Password',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _step == 1
                      ? 'Enter your registered email address to receive a password reset code.'
                      : _step == 2
                          ? 'Enter the reset code sent to your email.'
                          : 'Set a new password for your Reporter account.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 30),

                // Glass Form Card
                GlassCard(
                  borderRadius: 24,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // STEP 1: Enter Email
                      if (_step == 1) ...[
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Registered Email Address',
                            prefixIcon: Icon(Icons.email_outlined, color: AppTheme.primaryBlue),
                          ),
                        ),
                        if (authProvider.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            authProvider.errorMessage!,
                            style: const TextStyle(color: AppTheme.emergencyRed, fontSize: 13, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 24),
                        GradientButton(
                          text: 'Send Reset Code',
                          isLoading: authProvider.isLoading,
                          onPressed: _handleSendResetCode,
                        ),
                      ],

                      // STEP 2: Verify Code
                      if (_step == 2) ...[
                        Text(
                          _emailController.text,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryBlue),
                        ),
                        const SizedBox(height: 16),

                        // 6 OTP Box Inputs
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(
                            6,
                            (index) => SizedBox(
                              width: 38,
                              height: 48,
                              child: TextField(
                                controller: _otpControllers[index],
                                focusNode: _focusNodes[index],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                maxLength: 1,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  counterText: '',
                                  contentPadding: EdgeInsets.zero,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onChanged: (val) {
                                  if (val.isNotEmpty && index < 5) {
                                    _focusNodes[index + 1].requestFocus();
                                  } else if (val.isEmpty && index > 0) {
                                    _focusNodes[index - 1].requestFocus();
                                  }
                                },
                              ),
                            ),
                          ),
                        ),

                        if (authProvider.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            authProvider.errorMessage!,
                            style: const TextStyle(color: AppTheme.emergencyRed, fontSize: 13, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                        ],

                        const SizedBox(height: 20),

                        GradientButton(
                          text: 'Verify Code',
                          isLoading: authProvider.isLoading,
                          onPressed: _handleVerifyCode,
                        ),

                        const SizedBox(height: 16),

                        // Resend Option with Cooldown
                        TextButton(
                          onPressed: _resendCooldown > 0 ? null : _handleResendCode,
                          child: Text(
                            _resendCooldown > 0
                                ? 'Resend Code in ${_resendCooldown}s'
                                : 'Resend Code',
                            style: TextStyle(
                              color: _resendCooldown > 0 ? Colors.grey : AppTheme.primaryBlue,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],

                      // STEP 3: New Password
                      if (_step == 3) ...[
                        TextFormField(
                          controller: _newPasswordController,
                          obscureText: _obscureNewPassword,
                          decoration: InputDecoration(
                            labelText: 'New Password',
                            prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.primaryBlue),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureNewPassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                              onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          decoration: InputDecoration(
                            labelText: 'Confirm New Password',
                            prefixIcon: const Icon(Icons.lock_reset, color: AppTheme.primaryBlue),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                            ),
                          ),
                        ),

                        if (authProvider.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            authProvider.errorMessage!,
                            style: const TextStyle(color: AppTheme.emergencyRed, fontSize: 13, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                        ],

                        const SizedBox(height: 24),

                        GradientButton(
                          text: 'Reset Password',
                          isLoading: authProvider.isLoading,
                          onPressed: _handleResetPassword,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
