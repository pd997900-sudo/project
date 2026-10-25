import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/complaint_model.dart';
import '../../models/chat_message_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_badge.dart';

class ComplaintChatScreen extends StatefulWidget {
  final Complaint complaint;

  const ComplaintChatScreen({super.key, required this.complaint});

  @override
  State<ComplaintChatScreen> createState() => _ComplaintChatScreenState();
}

class _ComplaintChatScreenState extends State<ComplaintChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final chatProv = Provider.of<ChatProvider>(context, listen: false);
      chatProv.markMessagesAsRead(widget.complaint.complaintId, auth.selectedRole);
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSendMessage(AuthProvider auth, ChatProvider chatProv) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final currentUser = auth.currentUser;
    final currentRole = auth.selectedRole;
    final senderId = currentUser?.id ?? 'usr_${DateTime.now().millisecondsSinceEpoch}';
    final senderName = currentUser?.name ?? (currentRole == 'reporter' ? 'Citizen Reporter' : 'Community Volunteer');

    _messageController.clear();

    await chatProv.sendMessage(
      complaintId: widget.complaint.complaintId,
      senderId: senderId,
      senderName: senderName,
      senderRole: currentRole,
      messageText: text,
    );

    _scrollToBottom();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final chatProv = Provider.of<ChatProvider>(context);

    final complaint = widget.complaint;
    final messages = chatProv.getMessagesForComplaint(complaint.complaintId);
    final isReporter = auth.selectedRole == 'reporter';
    final isClosed = complaint.status == 'Completed' || complaint.status == 'Rejected';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.chat_bubble_rounded, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Chat: ${complaint.complaintId}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(
              isReporter ? 'Messaging Community Team' : 'Replying to Reporter',
              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.8)),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Center(
              child: StatusBadge(status: complaint.status),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.mainScreenBackground,
        child: SafeArea(
          child: Column(
            children: [
              // Header Complaint Info Mini Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  border: Border(bottom: BorderSide(color: AppTheme.primaryBlue.withOpacity(0.15))),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.engineering_rounded, color: AppTheme.primaryBlue, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            complaint.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppTheme.primaryDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '📍 ${complaint.address}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Messages List
              Expanded(
                child: messages.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryBlue.withOpacity(0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.forum_outlined,
                                  size: 48,
                                  color: AppTheme.primaryBlue,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                isReporter ? 'Start Conversation with Community Team' : 'No Messages Yet from Reporter',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppTheme.primaryDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isReporter
                                    ? 'Send a message regarding ${complaint.complaintId}. The community team handling this repair will respond to your queries.'
                                    : 'Messages sent by the citizen reporter for complaint ${complaint.complaintId} will appear here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          final isMe = (isReporter && msg.isReporter) || (!isReporter && msg.isCommunity);
                          final timeStr = DateFormat('h:mm a').format(msg.createdAt.toLocal());

                          return _buildChatBubble(msg: msg, isMe: isMe, timeStr: timeStr);
                        },
                      ),
              ),

              // Input Bar or Closed Notice
              if (isClosed)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    border: Border(top: BorderSide(color: Colors.grey.shade300)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        complaint.status == 'Completed' ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        size: 18,
                        color: complaint.status == 'Completed' ? AppTheme.successGreen : AppTheme.emergencyRed,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        complaint.status == 'Completed'
                            ? 'Complaint work completed. Conversation closed.'
                            : 'Complaint rejected. Messaging closed.',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryDark,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          focusNode: _focusNode,
                          textCapitalization: TextCapitalization.sentences,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                            hintText: isReporter
                                ? 'Type message to Community Team...'
                                : 'Type reply to Reporter...',
                            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) => _handleSendMessage(auth, chatProv),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: AppTheme.primaryBlue,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _handleSendMessage(auth, chatProv),
                          child: const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatBubble({
    required ChatMessage msg,
    required bool isMe,
    required String timeStr,
  }) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.primaryBlue : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
          border: isMe ? null : Border.all(color: AppTheme.primaryBlue.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    msg.isCommunity ? Icons.engineering_rounded : Icons.person_rounded,
                    size: 14,
                    color: AppTheme.primaryBlue,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    msg.senderName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: msg.isCommunity ? AppTheme.successGreen.withOpacity(0.15) : AppTheme.primaryBlue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      msg.isCommunity ? 'Community Team' : 'Reporter',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: msg.isCommunity ? AppTheme.successGreen : AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            Text(
              msg.messageText,
              style: TextStyle(
                fontSize: 14,
                color: isMe ? Colors.white : AppTheme.primaryDark,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe ? Colors.white70 : Colors.grey.shade600,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    msg.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 13,
                    color: Colors.white70,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
