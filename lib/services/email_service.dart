import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class EmailService {
  static const String serviceId = 'service_e3slln5';
  static const String templateId = 'template_qjl404b';
  static const String publicKey = 'utQYWnEXHYdXDbK5h';

  static String? lastError;

  /// Sends a 6-digit OTP verification code to the target user email
  /// using EmailJS REST API (service `service_e3slln5` and template `template_qjl404b`).
  static Future<bool> sendOtpEmail({
    required String userEmail,
    required String userName,
    required String otpCode,
  }) async {
    const url = 'https://api.emailjs.com/api/v1.0/email/send';
    lastError = null;

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'service_id': serviceId,
          'template_id': templateId,
          'user_id': publicKey,
          'template_params': {
            'passcode': otpCode,
            'time': '15 minutes',
            'to_name': userName,
            'name': userName,
            'user_name': userName,
            'to_email': userEmail,
            'email': userEmail,
            'user_email': userEmail,
            'send_to': userEmail,
            'otp_code': otpCode,
            'otp': otpCode,
            'code': otpCode,
            'verification_code': otpCode,
            'message': 'Your RoadWatch Account Verification OTP Code is $otpCode.',
          },
        }),
      );

      debugPrint('EmailJS Response Status (${response.statusCode}): ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ [EmailJS SUCCESS] OTP email delivered to $userEmail');
        return true;
      } else {
        final bodyText = response.body;
        if (bodyText.contains('insufficient authentication scopes') || bodyText.contains('Gmail_API')) {
          lastError = 'Gmail permission error: Please open EmailJS Dashboard and reconnect your Gmail service with "Send email" scope enabled.';
        } else {
          lastError = 'EmailJS Error (${response.statusCode}): ${response.body}';
        }
        debugPrint('⚠️ [EmailJS Failed]: $lastError');
        return false;
      }
    } catch (e) {
      final errStr = e.toString();
      if (errStr.contains('Failed to fetch') || errStr.contains('ClientException')) {
        lastError = 'Network/CORS block: Unable to connect to EmailJS. If you have an AdBlocker or Brave Shields active, please pause it for localhost.';
      } else {
        lastError = 'Network error sending OTP email: $e';
      }
      debugPrint('❌ EmailJS Exception: $e');
      return false;
    }
  }
}

