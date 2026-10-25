import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ProfileAvatarWidget extends StatelessWidget {
  final String? avatarUrl;
  final double radius;
  final VoidCallback? onTap;
  final Color? borderColor;
  final double borderWidth;

  const ProfileAvatarWidget({
    super.key,
    required this.avatarUrl,
    this.radius = 22,
    this.onTap,
    this.borderColor,
    this.borderWidth = 2,
  });

  static const String defaultAvatarUrl =
      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400&auto=format&fit=crop';

  @override
  Widget build(BuildContext context) {
    final cleanUrl = (avatarUrl != null && avatarUrl!.trim().isNotEmpty) ? avatarUrl!.trim() : null;

    Widget imageWidget = (cleanUrl != null) ? _buildImageFromUrl(cleanUrl) : _buildIconFallback();

    Widget avatarContent = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey.shade100,
        border: Border.all(
          color: borderColor ?? AppTheme.primaryBlue.withOpacity(0.3),
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: imageWidget,
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: avatarContent,
      );
    }
    return avatarContent;
  }

  Widget _buildImageFromUrl(String url) {
    if (url.startsWith('data:')) {
      try {
        final base64Str = url.contains(',') ? url.split(',').last : url;
        final bytes = base64Decode(base64Str);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildIconFallback(),
        );
      } catch (e) {
        return _buildIconFallback();
      }
    } else if (url.startsWith('http://') ||
        url.startsWith('https://') ||
        url.startsWith('blob:')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildIconFallback(),
      );
    } else {
      try {
        final file = File(url);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildIconFallback(),
          );
        }
      } catch (_) {}
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildIconFallback(),
      );
    }
  }

  Widget _buildIconFallback() {
    return Container(
      color: const Color(0xFFE2E8F0),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          size: radius * 1.15,
          color: const Color(0xFF475569),
        ),
      ),
    );
  }
}
