import 'package:flutter/material.dart';
import '../models/message.dart';
import '../data/mock_messages.dart';
import 'hover_icon_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MessagesPanel — Messaging interface shown in the right detail column.
// Three-screen flow: Message List → Message Detail (with replies) → Compose.
// ─────────────────────────────────────────────────────────────────────────────

class MessagesPanel extends StatefulWidget {
  final VoidCallback onClose;

  const MessagesPanel({
    super.key,
    required this.onClose,
  });

  @override
  State<MessagesPanel> createState() => MessagesPanelState();
}

class MessagesPanelState extends State<MessagesPanel> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  final TextEditingController _composeSubjectController =
      TextEditingController();
  final TextEditingController _composeBodyController = TextEditingController();
  final FocusNode _composeSubjectFocus = FocusNode();

  late List<Message> _allMessages;
  late List<Message> _filteredMessages;
  Message? _selectedMessage;
  String _selectedFolder = 'inbox';
  bool _isComposing = false;

  // ── Public methods for PosScreen Esc cascade ───────────────────────────────

  bool get isDetailOpen => _selectedMessage != null || _isComposing;

  void closeDetail() {
    setState(() {
      if (_isComposing) {
        _isComposing = false;
      } else {
        _selectedMessage = null;
      }
    });
  }

  void focusSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _allMessages = List<Message>.from(mockMessages);
    _applyFilters();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _replyController.dispose();
    _replyFocusNode.dispose();
    _composeSubjectController.dispose();
    _composeBodyController.dispose();
    _composeSubjectFocus.dispose();
    super.dispose();
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      var list = _allMessages.where((m) => m.folder == _selectedFolder).toList();
      if (query.isNotEmpty) {
        list = list.where((m) {
          return m.subject.toLowerCase().contains(query) ||
              m.body.toLowerCase().contains(query) ||
              m.senderName.toLowerCase().contains(query);
        }).toList();
      }
      list.sort((a, b) => b.date.compareTo(a.date));
      _filteredMessages = list;
    });
  }

  void _selectFolder(String folder) {
    setState(() {
      _selectedFolder = folder;
      _selectedMessage = null;
    });
    _applyFilters();
  }

  void _openMessage(Message msg) {
    setState(() {
      _selectedMessage = msg;
      if (!msg.isRead) {
        final idx = _allMessages.indexWhere((m) => m.id == msg.id);
        if (idx >= 0) {
          _allMessages[idx] = msg.copyWith(isRead: true);
          _selectedMessage = _allMessages[idx];
        }
      }
    });
    _applyFilters();
  }

  void _sendReply() {
    final text = _replyController.text.trim();
    if (text.isEmpty || _selectedMessage == null) return;
    final reply = MessageReply(
      id: 'reply-${DateTime.now().millisecondsSinceEpoch}',
      body: text,
      senderName: 'Аптека №47',
      senderRole: 'pharmacy',
      date: DateTime.now(),
    );
    setState(() {
      final idx = _allMessages.indexWhere((m) => m.id == _selectedMessage!.id);
      if (idx >= 0) {
        final updated = _allMessages[idx].copyWith(
          replies: [..._allMessages[idx].replies, reply],
        );
        _allMessages[idx] = updated;
        _selectedMessage = updated;
      }
    });
    _replyController.clear();
    _applyFilters();
  }

  void _openCompose() {
    setState(() {
      _isComposing = true;
      _composeSubjectController.clear();
      _composeBodyController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _composeSubjectFocus.requestFocus();
    });
  }

  void _sendNewMessage() {
    final subject = _composeSubjectController.text.trim();
    final body = _composeBodyController.text.trim();
    if (subject.isEmpty || body.isEmpty) return;
    final msg = Message(
      id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
      subject: subject,
      body: body,
      senderName: 'Аптека №47',
      folder: 'sent',
      senderRole: 'pharmacy',
      date: DateTime.now(),
      isRead: true,
    );
    setState(() {
      _allMessages.insert(0, msg);
      _isComposing = false;
      _selectedFolder = 'sent';
    });
    _applyFilters();
  }

  int get _unreadCount =>
      _allMessages.where((m) => m.folder == 'inbox' && !m.isRead).length;

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.03, 0),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut)),
            child: child,
          ),
        ),
        child: _isComposing
            ? _buildComposeScreen()
            : _selectedMessage != null
                ? _buildDetailScreen(_selectedMessage!)
                : _buildListScreen(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN 1 — MESSAGE LIST
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildListScreen() {
    return Column(
      key: const ValueKey('messages_list'),
      children: [
        _buildListHeader(),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        _buildFolderTabs(),
        _buildSearchField(),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        Expanded(child: _buildMessagesList()),
      ],
    );
  }

  Widget _buildListHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          const Icon(Icons.mail_outline_rounded,
              color: Color(0xFF1E7DC8), size: 17),
          const SizedBox(width: 8),
          const Text(
            'Повідомлення',
            style: TextStyle(
              color: Color(0xFF1C1C2E),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F8),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: const Text(
              'Ctrl+M',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const Spacer(),
          HoverIconButton(
            icon: Icons.edit_outlined,
            tooltip: 'Нове повідомлення',
            onTap: _openCompose,
          ),
          const SizedBox(width: 4),
          HoverIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Закрити',
            onTap: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildFolderTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          _FolderTab(
            label: 'Вхідні',
            icon: Icons.inbox_rounded,
            isActive: _selectedFolder == 'inbox',
            badgeCount: _unreadCount,
            onTap: () => _selectFolder('inbox'),
          ),
          const SizedBox(width: 8),
          _FolderTab(
            label: 'Надіслані',
            icon: Icons.send_rounded,
            isActive: _selectedFolder == 'sent',
            onTap: () => _selectFolder('sent'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SizedBox(
        height: 34,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: const TextStyle(fontSize: 13, color: Color(0xFF1C1C2E)),
          decoration: InputDecoration(
            hintText: 'Пошук повідомлень...',
            hintStyle:
                const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
            prefixIcon: const Icon(Icons.search_rounded,
                size: 18, color: Color(0xFF9CA3AF)),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 36, minHeight: 0),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            filled: true,
            fillColor: const Color(0xFFF4F5F8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1E7DC8)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_filteredMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _selectedFolder == 'inbox'
                  ? Icons.inbox_rounded
                  : Icons.send_rounded,
              size: 40,
              color: const Color(0xFFD1D5DB),
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isNotEmpty
                  ? 'Нічого не знайдено'
                  : _selectedFolder == 'inbox'
                      ? 'Немає вхідних повідомлень'
                      : 'Немає надісланих повідомлень',
              style: const TextStyle(
                  color: Color(0xFF9CA3AF), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _filteredMessages.length,
      separatorBuilder: (_, _) => const Divider(
          height: 1, thickness: 1, color: Color(0xFFF4F5F8)),
      itemBuilder: (context, index) {
        final msg = _filteredMessages[index];
        return _MessageListTile(
          message: msg,
          onTap: () => _openMessage(msg),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN 2 — MESSAGE DETAIL
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDetailScreen(Message msg) {
    return Column(
      key: ValueKey('msg_detail_${msg.id}'),
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              HoverIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Назад',
                onTap: () => setState(() => _selectedMessage = null),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  msg.subject,
                  style: const TextStyle(
                    color: Color(0xFF1C1C2E),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              HoverIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Закрити',
                onTap: widget.onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),

        // Message content + replies
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              // Original message
              _MessageBubble(
                senderName: msg.senderName,
                senderRole: msg.senderRole,
                body: msg.body,
                date: msg.date,
                tag: msg.tag,
                isOriginal: true,
              ),

              // Replies
              for (final reply in msg.replies) ...[
                const SizedBox(height: 12),
                _MessageBubble(
                  senderName: reply.senderName,
                  senderRole: reply.senderRole,
                  body: reply.body,
                  date: reply.date,
                  isOriginal: false,
                ),
              ],
            ],
          ),
        ),

        // Reply input
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _replyController,
                  focusNode: _replyFocusNode,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF1C1C2E)),
                  maxLines: 3,
                  minLines: 1,
                  onSubmitted: (_) => _sendReply(),
                  decoration: InputDecoration(
                    hintText: 'Написати відповідь...',
                    hintStyle: const TextStyle(
                        fontSize: 13, color: Color(0xFF9CA3AF)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    filled: true,
                    fillColor: const Color(0xFFF4F5F8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFF1E7DC8)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SendButton(onTap: _sendReply),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN 3 — COMPOSE NEW MESSAGE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildComposeScreen() {
    return Column(
      key: const ValueKey('messages_compose'),
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              HoverIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Назад',
                onTap: () => setState(() => _isComposing = false),
              ),
              const SizedBox(width: 8),
              const Text(
                'Нове повідомлення',
                style: TextStyle(
                  color: Color(0xFF1C1C2E),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              HoverIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Закрити',
                onTap: widget.onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),

        // Recipient selector
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: _ComposeRecipientField(),
        ),

        // Subject
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: TextField(
            controller: _composeSubjectController,
            focusNode: _composeSubjectFocus,
            style: const TextStyle(fontSize: 13, color: Color(0xFF1C1C2E)),
            decoration: InputDecoration(
              hintText: 'Тема',
              hintStyle:
                  const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: const Color(0xFFF4F5F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF1E7DC8)),
              ),
            ),
          ),
        ),

        // Body
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: TextField(
              controller: _composeBodyController,
              style:
                  const TextStyle(fontSize: 13, color: Color(0xFF1C1C2E)),
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: 'Текст повідомлення...',
                hintStyle:
                    const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: const Color(0xFFF4F5F8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1E7DC8)),
                ),
              ),
            ),
          ),
        ),

        // Send button
        const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              const Spacer(),
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: _sendNewMessage,
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Надіслати'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E7DC8),
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRIVATE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

// ── Folder tab ───────────────────────────────────────────────────────────────

class _FolderTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final int badgeCount;
  final VoidCallback onTap;

  const _FolderTab({
    required this.label,
    required this.icon,
    required this.isActive,
    this.badgeCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFFE8F3FB) : const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? const Color(0xFF1E7DC8)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 15,
                color: isActive
                    ? const Color(0xFF1E7DC8)
                    : const Color(0xFF6B7280)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? const Color(0xFF1E7DC8)
                    : const Color(0xFF6B7280),
              ),
            ),
            if (badgeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Message list tile ────────────────────────────────────────────────────────

class _MessageListTile extends StatefulWidget {
  final Message message;
  final VoidCallback onTap;

  const _MessageListTile({required this.message, required this.onTap});

  @override
  State<_MessageListTile> createState() => _MessageListTileState();
}

class _MessageListTileState extends State<_MessageListTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isUnread = !msg.isRead;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: _hovered
              ? const Color(0xFFF8FAFC)
              : isUnread
                  ? const Color(0xFFF0F7FF)
                  : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar / role icon
              _SenderAvatar(senderRole: msg.senderRole),
              const SizedBox(width: 10),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sender + date row
                    Row(
                      children: [
                        if (isUnread)
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1E7DC8),
                              shape: BoxShape.circle,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            msg.senderName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: const Color(0xFF1C1C2E),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _formatDate(msg.date),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // Subject
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            msg.subject,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: const Color(0xFF1C1C2E),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (msg.replies.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.reply_rounded,
                              size: 14, color: const Color(0xFF9CA3AF)),
                          const SizedBox(width: 2),
                          Text(
                            '${msg.replies.length}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),

                    // Preview
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            msg.body.replaceAll('\n', ' '),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9CA3AF),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (msg.tag != null) ...[
                          const SizedBox(width: 6),
                          _TagBadge(tag: msg.tag!),
                        ],
                      ],
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
}

// ── Sender avatar ────────────────────────────────────────────────────────────

class _SenderAvatar extends StatelessWidget {
  final String senderRole;

  const _SenderAvatar({required this.senderRole});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color bg, Color fg) = switch (senderRole) {
      'office' => (
          Icons.business_rounded,
          const Color(0xFFE8F3FB),
          const Color(0xFF1E7DC8)
        ),
      'warehouse' => (
          Icons.warehouse_rounded,
          const Color(0xFFFFF3E0),
          const Color(0xFFE67E22)
        ),
      'pharmacy' => (
          Icons.local_pharmacy_rounded,
          const Color(0xFFE8F5E9),
          const Color(0xFF2E7D32)
        ),
      _ => (
          Icons.person_rounded,
          const Color(0xFFF4F5F8),
          const Color(0xFF6B7280)
        ),
    };

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: fg),
    );
  }
}

// ── Tag badge ────────────────────────────────────────────────────────────────

class _TagBadge extends StatelessWidget {
  final String tag;

  const _TagBadge({required this.tag});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (tag) {
      'Важливо' || 'Терміново' => (
          const Color(0xFFFEE2E2),
          const Color(0xFFDC2626)
        ),
      'Дефектура' => (const Color(0xFFFFF3E0), const Color(0xFFE67E22)),
      'Акція' => (const Color(0xFFE8F5E9), const Color(0xFF2E7D32)),
      'Запит' => (const Color(0xFFE8F3FB), const Color(0xFF1E7DC8)),
      'Рекламація' => (const Color(0xFFFCE4EC), const Color(0xFFC62828)),
      'Логістика' => (const Color(0xFFEDE7F6), const Color(0xFF5E35B1)),
      _ => (const Color(0xFFF4F5F8), const Color(0xFF6B7280)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

// ── Message bubble (detail screen) ───────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final String senderName;
  final String senderRole;
  final String body;
  final DateTime date;
  final String? tag;
  final bool isOriginal;

  const _MessageBubble({
    required this.senderName,
    required this.senderRole,
    required this.body,
    required this.date,
    this.tag,
    required this.isOriginal,
  });

  @override
  Widget build(BuildContext context) {
    final isPharmacy = senderRole == 'pharmacy';

    return Align(
      alignment: isPharmacy ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isPharmacy
              ? const Color(0xFFE8F3FB)
              : const Color(0xFFF4F5F8),
          borderRadius: BorderRadius.circular(12).copyWith(
            bottomRight:
                isPharmacy ? const Radius.circular(2) : null,
            bottomLeft:
                !isPharmacy ? const Radius.circular(2) : null,
          ),
          border: Border.all(
            color: isPharmacy
                ? const Color(0xFFBFCBFB)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                _SenderAvatar(senderRole: senderRole),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        senderName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1C1C2E),
                        ),
                      ),
                      Text(
                        _formatDateTime(date),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
                if (tag != null) _TagBadge(tag: tag!),
              ],
            ),
            const SizedBox(height: 10),

            // Body
            Text(
              body,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF374151),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Send button ──────────────────────────────────────────────────────────────

class _SendButton extends StatefulWidget {
  final VoidCallback onTap;

  const _SendButton({required this.onTap});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xFF1565C0)
                : const Color(0xFF1E7DC8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

// ── Compose recipient field ──────────────────────────────────────────────────

class _ComposeRecipientField extends StatefulWidget {
  @override
  State<_ComposeRecipientField> createState() => _ComposeRecipientFieldState();
}

class _ComposeRecipientFieldState extends State<_ComposeRecipientField> {
  String _selected = 'Головний офіс';

  static const _recipients = [
    'Головний офіс',
    'Центральний склад',
    'Маркетинг',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Кому:',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F5F8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selected,
                isExpanded: true,
                icon: const Icon(Icons.expand_more_rounded,
                    size: 18, color: Color(0xFF9CA3AF)),
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF1C1C2E)),
                items: _recipients.map((r) {
                  return DropdownMenuItem(value: r, child: Text(r));
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selected = v);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

String _formatDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inDays == 0) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  } else if (diff.inDays == 1) {
    return 'Вчора';
  } else if (diff.inDays < 7) {
    const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'];
    return days[date.weekday - 1];
  }
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
}

String _formatDateTime(DateTime date) {
  final d =
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  final t =
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  return '$d о $t';
}
