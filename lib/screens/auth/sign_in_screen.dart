import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/gradient_button.dart';
import '../../providers/auth_provider.dart';
import '../../providers/complaint_provider.dart';
import '../reporter/reporter_main_screen.dart';
import '../community/community_main_screen.dart';
import 'sign_up_screen.dart';
import 'forgot_password_screen.dart';

class SignInScreen extends StatefulWidget {
  final String? portalRole;
  final String? initialEmail;
  final String? initialPassword;
  const SignInScreen({
    super.key,
    this.portalRole,
    this.initialEmail,
    this.initialPassword,
  });

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _obscurePassword = true;
  bool _rememberMe = true;
  String? _selectedAccountEmail;
  bool _isHoveringSuggestions = false;

  String _getActiveRole(AuthProvider authProvider) {
    return (widget.portalRole ?? authProvider.selectedRole).toLowerCase();
  }

  @override
  void initState() {
    super.initState();
    // Requirement 1: Keep Email and Password visually empty on fresh login screen load.
    // Do not prepopulate or preload either field from app state, shared preferences, local storage, or cached values.
    _emailController.clear();
    _passwordController.clear();
    _emailController.addListener(_onEmailChanged);
    _emailFocusNode.addListener(_onFocusChanged);
    _passwordFocusNode.addListener(_onFocusChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.ensureStorageLoaded();
      if (!mounted) return;
      authProvider.clearError();

      final currentRole = _getActiveRole(authProvider);
      if (widget.portalRole != null && authProvider.selectedRole != widget.portalRole) {
        authProvider.setSelectedRole(widget.portalRole!);
      }

      if (mounted) {
        setState(() {
          _rememberMe = authProvider.getRememberMe(currentRole);
          _emailController.clear();
          _passwordController.clear();
          _selectedAccountEmail = null;
          _isHoveringSuggestions = false;
        });
      }
    });
  }

  void _onEmailChanged() {
    final text = _emailController.text.trim();
    if (_selectedAccountEmail != null && text.toLowerCase() != _selectedAccountEmail!.toLowerCase()) {
      setState(() {
        _selectedAccountEmail = null;
      });
    } else {
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _onFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _selectSavedAccount(String email, String password) {
    setState(() {
      _selectedAccountEmail = email;
      _emailController.text = email;
      _passwordController.text = password;
      _isHoveringSuggestions = false;
    });
    FocusScope.of(context).requestFocus(_passwordFocusNode);
  }

  @override
  void dispose() {
    _emailController.removeListener(_onEmailChanged);
    _emailFocusNode.removeListener(_onFocusChanged);
    _passwordFocusNode.removeListener(_onFocusChanged);
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleSignIn() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    final userRole = _getActiveRole(authProvider);
    final success = await authProvider.signIn(
      email: email,
      password: password,
      role: userRole,
    );

    if (!mounted) return;

    if (success) {
      await authProvider.saveCredentials(
        email: email,
        password: password,
        rememberMe: _rememberMe,
        role: userRole,
      );

      if (!mounted) return;

      final actualRole = (authProvider.currentUser?.role ?? authProvider.selectedRole).toLowerCase();
      final isReporter = actualRole == 'reporter';

      // Clear fields before navigating so returning to Sign In page leaves fields blank by default
      _emailController.clear();
      _passwordController.clear();
      _selectedAccountEmail = null;
      _isHoveringSuggestions = false;

      // Ensure complaints, votes, and feedbacks are refreshed with authenticated credentials
      Provider.of<ComplaintProvider>(context, listen: false).refreshComplaints();

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => isReporter
              ? const ReporterMainScreen()
              : const CommunityMainScreen(),
        ),
        (route) => false,
      );
    } else {
      final errMsg = authProvider.errorMessage;
      if (errMsg != null && mounted) {
        final isUnconfirmed = errMsg.toLowerCase().contains('email not confirmed');
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger != null) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text(errMsg),
              backgroundColor: AppTheme.emergencyRed,
              duration: Duration(seconds: isUnconfirmed ? 8 : 5),
              action: isUnconfirmed
                  ? SnackBarAction(
                      label: 'Resend Email',
                      textColor: Colors.white,
                      onPressed: () async {
                        final resent = await authProvider.resendConfirmationEmail(email);
                        if (mounted) {
                          final innerMessenger = ScaffoldMessenger.maybeOf(context);
                          if (innerMessenger != null) {
                            innerMessenger.hideCurrentSnackBar();
                            innerMessenger.showSnackBar(
                              SnackBar(
                                content: Text(authProvider.errorMessage ?? 'Confirmation email sent! Check your inbox.'),
                                backgroundColor: resent ? AppTheme.successGreen : AppTheme.emergencyRed,
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          }
                        }
                      },
                    )
                  : null,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final activeRole = _getActiveRole(authProvider);
    final isReporter = activeRole == 'reporter';

    final savedAccounts = authProvider.getAvailableSavedAccounts(activeRole);
    final typedEmail = _emailController.text.trim().toLowerCase();

    final matchingAccounts = savedAccounts.entries.where((entry) {
      final savedEmail = entry.key.trim();
      if (typedEmail.isEmpty) return true;
      if (_selectedAccountEmail != null && savedEmail.toLowerCase() == _selectedAccountEmail!.toLowerCase()) return true;
      return savedEmail.toLowerCase().contains(typedEmail);
    }).toList();

    final showSuggestions = (_emailFocusNode.hasFocus ||
            _isHoveringSuggestions ||
            (typedEmail.isNotEmpty && _selectedAccountEmail == null)) &&
        matchingAccounts.isNotEmpty &&
        _selectedAccountEmail == null;

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
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                ),
                const SizedBox(height: 10),

                // Header
                const Text(
                  'Welcome Back!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sign in as ${isReporter ? "Reporter" : "Community Volunteer"}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 18),

                // Role Toggle Selector Segment
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (authProvider.selectedRole != 'reporter') {
                              authProvider.setSelectedRole('reporter');
                              setState(() {
                                _selectedAccountEmail = null;
                                _isHoveringSuggestions = false;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isReporter ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                'Reporter Portal',
                                style: TextStyle(
                                  color: isReporter ? AppTheme.primaryDark : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (authProvider.selectedRole != 'community') {
                              authProvider.setSelectedRole('community');
                              setState(() {
                                _selectedAccountEmail = null;
                                _isHoveringSuggestions = false;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: !isReporter ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                'Community Portal',
                                style: TextStyle(
                                  color: !isReporter ? AppTheme.primaryDark : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Glass Form Container
                GlassCard(
                  borderRadius: 24,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Email Field
                      TextField(
                        controller: _emailController,
                        focusNode: _emailFocusNode,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: null, // Avoid shared localhost browser credential auto-dump
                        enableSuggestions: false,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) {
                          FocusScope.of(context).requestFocus(_passwordFocusNode);
                        },
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        cursorColor: AppTheme.primaryBlue,
                        decoration: const InputDecoration(
                          labelText: 'Email Address',
                          labelStyle: TextStyle(color: Colors.black54),
                          prefixIcon: Icon(Icons.email_outlined, color: AppTheme.primaryBlue),
                        ),
                      ),

                      // Role-Specific Saved Account Suggestions (when focused or typing)
                      if (showSuggestions) ...[
                        const SizedBox(height: 8),
                        MouseRegion(
                          onEnter: (_) {
                            if (!_isHoveringSuggestions) {
                              setState(() => _isHoveringSuggestions = true);
                            }
                          },
                          onExit: (_) {
                            if (_isHoveringSuggestions) {
                              setState(() => _isHoveringSuggestions = false);
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.35), width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryBlue.withOpacity(0.08),
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isReporter ? Icons.person_pin_circle_rounded : Icons.engineering_rounded,
                                        size: 15,
                                        color: AppTheme.primaryBlue,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Saved ${isReporter ? "Reporter" : "Community"} Accounts',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ...matchingAccounts.map((entry) {
                                  final isSelected = _selectedAccountEmail?.toLowerCase() == entry.key.toLowerCase();
                                  return Material(
                                    color: isSelected ? AppTheme.primaryBlue.withOpacity(0.08) : Colors.transparent,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(color: Colors.grey.shade100),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Listener(
                                              behavior: HitTestBehavior.opaque,
                                              onPointerDown: (_) => _selectSavedAccount(entry.key, entry.value),
                                              child: InkWell(
                                                onTap: () => _selectSavedAccount(entry.key, entry.value),
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        isSelected ? Icons.check_circle_rounded : Icons.account_circle_outlined,
                                                        size: 18,
                                                        color: isSelected ? AppTheme.primaryBlue : Colors.grey.shade600,
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Text(
                                                          entry.key,
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                            color: isSelected ? AppTheme.primaryDark : Colors.black87,
                                                          ),
                                                        ),
                                                      ),
                                                      if (isSelected)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: AppTheme.primaryBlue.withOpacity(0.12),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: const Text(
                                                            'Selected',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.bold,
                                                              color: AppTheme.primaryBlue,
                                                            ),
                                                          ),
                                                        )
                                                      else
                                                        const Text(
                                                          'Autofill',
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w600,
                                                            color: AppTheme.primaryBlue,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            tooltip: 'Remove',
                                            onPressed: () async {
                                              await authProvider.removeSavedAccount(entry.key, activeRole);
                                              if (!mounted) return;
                                              if (_emailController.text.trim().toLowerCase() == entry.key.toLowerCase()) {
                                                _emailController.clear();
                                                _passwordController.clear();
                                                _selectedAccountEmail = null;
                                              }
                                              setState(() {});
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),

                      // Password Field
                      TextField(
                        controller: _passwordController,
                        focusNode: _passwordFocusNode,
                        obscureText: _obscurePassword,
                        obscuringCharacter: '•',
                        autofillHints: null, // Avoid shared localhost browser credential auto-dump
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.done,
                        enableSuggestions: false,
                        autocorrect: false,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        cursorColor: AppTheme.primaryBlue,
                        onSubmitted: (_) => _handleSignIn(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle: const TextStyle(color: Colors.black54),
                          prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.primaryBlue),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Save Account / Remember Me & Forgot Password Row
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _rememberMe,
                              activeColor: AppTheme.primaryBlue,
                              onChanged: (val) async {
                                final isChecked = val ?? true;
                                setState(() {
                                  _rememberMe = isChecked;
                                });
                                await authProvider.setRememberMe(isChecked, activeRole);
                                if (!mounted) return;
                                if (!isChecked) {
                                  await authProvider.clearSavedCredentials(activeRole);
                                  if (!mounted) return;
                                  setState(() {
                                    _selectedAccountEmail = null;
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Save Account',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black87),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ForgotPasswordScreen(
                                    initialEmail: _emailController.text.trim(),
                                    portalRole: _getActiveRole(authProvider),
                                  ),
                                ),
                              );
                            },
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        ],
                      ),

                      if (authProvider.errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          authProvider.errorMessage!,
                          style: const TextStyle(color: AppTheme.emergencyRed, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Sign In Button
                      GradientButton(
                        text: 'Sign In',
                        isLoading: authProvider.isLoading,
                        onPressed: _handleSignIn,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Link to Sign Up
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: TextStyle(color: Colors.white.withOpacity(0.8)),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SignUpScreen(
                              portalRole: _getActiveRole(authProvider),
                            ),
                          ),
                        );
                      },
                      child: const Text(
                        'Sign Up',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
