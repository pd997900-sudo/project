import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/gradient_button.dart';
import '../../providers/auth_provider.dart';
import 'sign_in_screen.dart';

class SignUpScreen extends StatefulWidget {
  final String? portalRole;
  const SignUpScreen({super.key, this.portalRole});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.portalRole != null && mounted) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        if (authProvider.selectedRole != widget.portalRole) {
          authProvider.setSelectedRole(widget.portalRole!);
        }
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _getActiveRole(AuthProvider authProvider) {
    final candidate = (widget.portalRole ?? authProvider.selectedRole).trim().toLowerCase();
    return (candidate == 'reporter' || candidate == 'community') ? candidate : 'reporter';
  }

  void _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Passwords do not match'),
            backgroundColor: AppTheme.emergencyRed,
          ),
        );
      }
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final activeRole = _getActiveRole(authProvider);
    
    // Initiate Registration -> Sends EmailJS OTP (template_qjl404b, service_e3slln5)
    final success = await authProvider.initiateRegistration(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: '',
      password: _passwordController.text.trim(),
      role: activeRole,
    );

    if (!mounted) return;

    if (!success) {
      if (authProvider.errorMessage != null && mounted) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(authProvider.errorMessage!),
              backgroundColor: AppTheme.emergencyRed,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
      return;
    }
    _showOtpVerificationDialog(authProvider);
  }

  /// Interactive OTP Verification Modal Dialog
  void _showOtpVerificationDialog(AuthProvider authProvider) {
    final otpControllers = List.generate(6, (_) => TextEditingController());
    final focusNodes = List.generate(6, (_) => FocusNode());
    int resendCooldown = 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mark_email_read_rounded, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Email OTP Verification',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'A 6-digit verification code was sent to your email:\n${_emailController.text}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 20),

                  // 6 OTP Box Inputs
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                      6,
                      (index) => SizedBox(
                        width: 38,
                        height: 48,
                        child: TextField(
                          controller: otpControllers[index],
                          focusNode: focusNodes[index],
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
                              focusNodes[index + 1].requestFocus();
                            } else if (val.isEmpty && index > 0) {
                              focusNodes[index - 1].requestFocus();
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
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.emergencyRed, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],

                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: authProvider.isLoading
                        ? null
                        : () async {
                            final resent = await authProvider.resendRegistrationOtp();
                            setModalState(() {
                              if (resent) {
                                for (var c in otpControllers) {
                                  c.clear();
                                }
                              }
                            });
                          },
                    child: const Text(
                      'Request New Code',
                      style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: authProvider.isLoading
                      ? null
                      : () async {
                          final enteredCode = otpControllers.map((c) => c.text).join();
                          final success = await authProvider.verifyOtpAndCompleteSignup(enteredCode);

                          if (success && mounted) {
                            Navigator.pop(context); // Close OTP dialog

                            final activeRole = _getActiveRole(authProvider);
                            _showAccountCreatedSuccessDialog(
                              name: _nameController.text.trim(),
                              email: _emailController.text.trim(),
                              role: activeRole,
                            );
                          } else {
                            setModalState(() {});
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Verify & Register'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final activeRole = _getActiveRole(authProvider);

    return Scaffold(
      body: Container(
        decoration: AppTheme.gradientBackgroundDecoration,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                  ),
                  const SizedBox(height: 10),

                  const Text(
                    'Create Account',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Registering as ${activeRole == "reporter" ? "Citizen Reporter" : "Community Volunteer"}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Glass Registration Form
                  GlassCard(
                    borderRadius: 24,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // Full Name
                        TextFormField(
                          controller: _nameController,
                          validator: (val) => val == null || val.isEmpty ? 'Enter full name' : null,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            prefixIcon: Icon(Icons.person_outline, color: AppTheme.primaryBlue),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Email Address
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          validator: (val) => val == null || !val.contains('@') ? 'Enter valid email' : null,
                          decoration: const InputDecoration(
                            labelText: 'Email Address',
                            prefixIcon: Icon(Icons.email_outlined, color: AppTheme.primaryBlue),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          validator: (val) => val == null || val.length < 6 ? 'Password must be at least 6 chars' : null,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.primaryBlue),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Confirm Password
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          validator: (val) => val == null || val.isEmpty ? 'Confirm password' : null,
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
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

                        // Submit Sign Up & Send EmailJS OTP
                        GradientButton(
                          text: 'Verify Email',
                          isLoading: authProvider.isLoading,
                          onPressed: _handleSignUp,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Redirect to Sign In Page
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: TextStyle(color: Colors.white.withOpacity(0.8)),
                      ),
                      GestureDetector(
                        onTap: () {
                          final authProvider = Provider.of<AuthProvider>(context, listen: false);
                          final activeRole = _getActiveRole(authProvider);
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SignInScreen(portalRole: activeRole),
                            ),
                          );
                        },
                        child: const Text(
                          'Sign In',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAccountCreatedSuccessDialog({
    required String name,
    required String email,
    required String role,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 12,
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Green animated success badge
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.successGreen.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: CircleAvatar(
                      radius: 30,
                      backgroundColor: AppTheme.successGreen,
                      child: Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Registration Successful',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Welcome $name! Your account has been registered successfully. A confirmation email was sent to $email. Please check your inbox and click "Confirm email address" before signing in.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 20),

                // Account Summary Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow(Icons.person_outline, 'Full Name', name),
                      const Divider(height: 16),
                      _buildDetailRow(Icons.email_outlined, 'Email', email),
                      const Divider(height: 16),
                      _buildDetailRow(
                        Icons.badge_outlined,
                        'Role',
                        role.toLowerCase() == 'reporter' ? 'Citizen Reporter' : 'Community Volunteer',
                        valueColor: AppTheme.primaryBlue,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Sign In Action Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.login_rounded, size: 20),
                    label: const Text(
                      'Sign In Now',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.pop(dialogCtx); // Close dialog
                      if (!mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => SignInScreen(
                            portalRole: role,
                            initialEmail: email,
                            initialPassword: _passwordController.text.trim(),
                          ),
                        ),
                        (route) => false,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const Spacer(),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: valueColor ?? AppTheme.primaryDark,
            ),
          ),
        ),
      ],
    );
  }
}
