import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message_model.dart';
import '../services/supabase_service.dart';

class ChatProvider extends ChangeNotifier {
  static const String _chatStorageKey = 'roadwatch_complaint_chat_messages_v1';
  List<ChatMessage> _messages = [];
  bool _isLoading = false;

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;

  ChatProvider() {
    _initChatStorage();
  }

  Future<void> _initChatStorage() async {
    await _loadMessagesFromStorage();
  }

  /// Load stored messages from SharedPreferences & Supabase
  Future<void> _loadMessagesFromStorage() async {
    _isLoading = true;
    notifyListeners();

    try {
      final Map<String, ChatMessage> map = {};

      // 1. Load from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final storedJson = prefs.getString(_chatStorageKey);
      if (storedJson != null && storedJson.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(storedJson);
          final loaded = decoded.map((item) => ChatMessage.fromJson(item)).toList();
          for (var m in loaded) {
            map[m.messageId] = m;
          }
        } catch (e) {
          debugPrint('Error parsing stored chat messages: $e');
        }
      }

      // 2. Sync from Supabase community_messages table if connected
      if (SupabaseService.isConnected) {
        try {
          final remoteData = await SupabaseService.client
              ?.from('community_messages')
              .select('*');
          if (remoteData != null) {
            for (var row in remoteData) {
              final msg = ChatMessage.fromJson(row);
              map[msg.messageId] = msg;
            }
          }
        } catch (e) {
          debugPrint('Notice loading messages from Supabase: $e');
        }
      }

      _messages = map.values.toList();
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } catch (e) {
      debugPrint('Error loading chat messages: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Save messages list to SharedPreferences
  Future<void> _saveMessagesToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _messages.map((m) => m.toJson()).toList();
      await prefs.setString(_chatStorageKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving chat messages to storage: $e');
    }
  }

  /// Get messages specifically linked to a complaint ID
  List<ChatMessage> getMessagesForComplaint(String complaintId) {
    final cleanId = complaintId.trim();
    return _messages.where((m) => m.complaintId.trim() == cleanId).toList();
  }

  /// Get unread message count for a specific complaint & role
  int getUnreadCountForComplaint(String complaintId, String userRole) {
    final cleanId = complaintId.trim();
    final isUserReporter = userRole.toLowerCase() == 'reporter';
    return _messages.where((m) {
      if (m.complaintId.trim() != cleanId) return false;
      if (m.isRead) return false;
      // If user is reporter, show unread count for messages sent by community
      // If user is community, show unread count for messages sent by reporter
      return isUserReporter ? m.isCommunity : m.isReporter;
    }).length;
  }

  /// Mark all messages for a complaint as read
  Future<void> markMessagesAsRead(String complaintId, String userRole) async {
    final cleanId = complaintId.trim();
    final isUserReporter = userRole.toLowerCase() == 'reporter';
    bool changed = false;

    for (int i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      if (m.complaintId.trim() == cleanId && !m.isRead) {
        final shouldMark = isUserReporter ? m.isCommunity : m.isReporter;
        if (shouldMark) {
          _messages[i] = m.copyWith(isRead: true);
          changed = true;
        }
      }
    }

    if (changed) {
      await _saveMessagesToStorage();
      notifyListeners();
    }
  }

  /// Send a new message linked to a specific complaint
  Future<ChatMessage> sendMessage({
    required String complaintId,
    required String senderId,
    required String senderName,
    required String senderRole,
    required String messageText,
  }) async {
    final cleanText = messageText.trim();
    final msgId = 'msg_${DateTime.now().millisecondsSinceEpoch}';

    final newMessage = ChatMessage(
      messageId: msgId,
      complaintId: complaintId.trim(),
      senderId: senderId.trim(),
      senderName: senderName.trim().isNotEmpty ? senderName.trim() : (senderRole == 'reporter' ? 'Citizen Reporter' : 'Community Squad'),
      senderRole: senderRole.trim(),
      messageText: cleanText,
      createdAt: DateTime.now(),
      isRead: false,
    );

    _messages.add(newMessage);
    _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    await _saveMessagesToStorage();

    // Sync to Supabase community_messages table if connected
    if (SupabaseService.isConnected) {
      try {
        await SupabaseService.client
            ?.from('community_messages')
            .insert(newMessage.toJson());
      } catch (e) {
        debugPrint('Notice sending message to Supabase: $e');
      }
    }

    notifyListeners();
    return newMessage;
  }
}
