import 'dart:async';
import 'dart:math' show min, pi;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'cards.dart';
import 'client.dart' show holloMaxPhotos;
import 'links.dart';
import 'models.dart';
import 'store.dart';

// The chat screen, in plain Material widgets. Black and white by default,
// with a dark version; pass a HolloTheme to match the host app.

/// The chat's colours and title. Every field is optional.
@immutable
class HolloTheme {
  const HolloTheme({
    this.accent = const Color(0xFF0B0B0C),
    this.background = const Color(0xFFFFFFFF),
    this.text = const Color(0xFF0B0B0C),
    this.muted = const Color(0xFF8A8A8E),
    this.bubble = const Color(0xFFF1F1F0),
    this.title = 'Support',
    this.fontFamily,
  });

  /// Ink on white.
  static const HolloTheme light = HolloTheme();

  /// White on ink, used when the device is in dark mode.
  static const HolloTheme dark = HolloTheme(
    accent: Color(0xFFFFFFFF),
    background: Color(0xFF0B0B0C),
    text: Color(0xFFF5F5F4),
    muted: Color(0xFF8A8A8E),
    bubble: Color(0xFF1F1F21),
  );

  /// Buttons, the send button and the user's own bubbles.
  final Color accent;
  final Color background;
  final Color text;

  /// Secondary text: the subtitle, labels, card descriptions.
  final Color muted;

  /// Replies' bubbles, borders and dividers.
  final Color bubble;

  /// The header title when the dashboard has no profile name.
  final String title;
  final String? fontFamily;

  HolloTheme copyWith({
    Color? accent,
    Color? background,
    Color? text,
    Color? muted,
    Color? bubble,
    String? title,
    String? fontFamily,
  }) =>
      HolloTheme(
        accent: accent ?? this.accent,
        background: background ?? this.background,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        bubble: bubble ?? this.bubble,
        title: title ?? this.title,
        fontFamily: fontFamily ?? this.fontFamily,
      );
}

/// [HolloTheme] with the dashboard's colours on top, for the look the chat
/// is shown in. A colour the dashboard leaves unset keeps the app's.
class _ChatTheme extends HolloTheme {
  const _ChatTheme({
    required super.accent,
    required super.background,
    required super.text,
    required super.muted,
    required super.bubble,
    required super.title,
    super.fontFamily,
    required this.onAccent,
    required this.incomingText,
  });

  factory _ChatTheme.resolve(
    HolloTheme local,
    HolloRemoteTheme remote, {
    required bool dark,
  }) {
    Color? pick(HolloRemoteColor? color) {
      final value = color?.pick(dark: dark);
      return value == null ? null : Color(value);
    }

    return _ChatTheme(
      accent: pick(remote.accent) ?? local.accent,
      background: pick(remote.background) ?? local.background,
      text: local.text,
      muted: local.muted,
      bubble: pick(remote.incoming) ?? local.bubble,
      title: remote.title ?? local.title,
      fontFamily: local.fontFamily,
      // Text on the accent has always been the background colour.
      onAccent: pick(remote.onAccent) ?? local.background,
      incomingText: pick(remote.incomingText) ?? local.text,
    );
  }

  /// Text and icons on the accent colour.
  final Color onAccent;

  /// Text in bubbles from the team and the AI.
  final Color incomingText;
}

/// Where the "Runs on Hollo" footer goes; ref counts taps from the chat.
final Uri _brandingUrl = Uri.parse('https://hollo.so/?ref=chat');

/// Lets the user choose up to `limit` photos, returned as JPEG bytes that
/// are already resized and compressed. Empty when they cancel.
typedef HolloPhotoPicker = Future<List<Uint8List>> Function(int limit);

/// The chat screen itself, wired to a [HolloStore]. Apps use `HolloChat`.
class HolloChatView extends StatefulWidget {
  const HolloChatView({
    super.key,
    required this.store,
    required this.theme,
    required this.os,
    required this.onOffer,
    required this.onLink,
    required this.openUrl,
    required this.pickPhotos,
    this.onClose,
    this.dark = false,
  });

  final HolloStore store;
  final HolloTheme theme;

  /// The chat is shown dark, so dashboard colours use their dark half.
  final bool dark;

  /// `ios`, `android` or `web`: picks the store page for review cards.
  final String os;
  final void Function(HolloOffer offer) onOffer;
  final void Function(HolloMessage message) onLink;
  final Future<bool> Function(Uri uri) openUrl;

  /// Behind the attach button. The real one is image_picker; tests fake it.
  final HolloPhotoPicker pickPhotos;

  /// Shows a Done button when set (the presented chat).
  final VoidCallback? onClose;

  @override
  State<HolloChatView> createState() => _HolloChatViewState();
}

class _HolloChatViewState extends State<HolloChatView> {
  final TextEditingController _draft = TextEditingController();

  /// Photos chosen for the next message, shown above the composer.
  final List<Uint8List> _photos = <Uint8List>[];
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    // Opening marks replies read, which rebuilds widgets elsewhere (the
    // unread badge). Flutter forbids that mid-build, so wait for the frame.
    scheduleMicrotask(() {
      if (!mounted) return;
      _shown = true;
      widget.store.chatShown();
    });
  }

  @override
  void dispose() {
    _draft.dispose();
    if (_shown) scheduleMicrotask(widget.store.chatHidden);
    super.dispose();
  }

  Future<void> _send() async {
    final text = _draft.text;
    final photos = List<Uint8List>.of(_photos);
    if (text.trim().isEmpty && photos.isEmpty) return;
    if (widget.store.sending) return;
    _draft.clear();
    setState(_photos.clear);
    try {
      await widget.store.send(text, photos: photos);
    } catch (_) {
      // Put it back so the user can try again.
      if (!mounted) return;
      if (_draft.text.isEmpty) _draft.text = text;
      if (_photos.isEmpty) setState(() => _photos.addAll(photos));
    }
  }

  Future<void> _attach() async {
    final room = holloMaxPhotos - _photos.length;
    if (room <= 0 || widget.store.sending) return;
    final List<Uint8List> picked;
    try {
      picked = await widget.pickPhotos(room);
    } catch (_) {
      // No access to the photo library, or the picker failed: nothing to add.
      return;
    }
    if (!mounted || picked.isEmpty) return;
    setState(() {
      _photos.addAll(picked.take(holloMaxPhotos - _photos.length));
    });
  }

  void _openPhotos(HolloMessage message, int index) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _PhotoViewer(urls: message.photos, initial: index),
        ),
      ),
    );
  }

  void _pressCard(HolloMessage message, HolloCard card) {
    switch (card.kind) {
      case HolloCardKind.review:
        final url = reviewUrl(widget.os, message.payload);
        final uri = url == null ? null : Uri.tryParse(url);
        if (uri != null) unawaited(widget.openUrl(uri));
      case HolloCardKind.link:
        widget.onLink(message);
      case HolloCardKind.offer:
        widget.onOffer(
          HolloOffer(
            ref: message.payload['ref'] is String
                ? message.payload['ref'] as String
                : '',
            title: card.title,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final store = widget.store;
        final theme = _ChatTheme.resolve(
          widget.theme,
          store.remoteTheme,
          dark: widget.dark,
        );
        return Scaffold(
          backgroundColor: theme.background,
          body: SafeArea(
            child: DefaultTextStyle.merge(
              style: TextStyle(color: theme.text, fontFamily: theme.fontFamily),
              child: Column(
                children: [
                  _Header(
                    theme: theme,
                    profile: store.profile,
                    onClose: widget.onClose,
                  ),
                  Divider(height: 1, thickness: 1, color: theme.bubble),
                  Expanded(
                    child: store.messages.isEmpty
                        ? _Welcome(theme: theme, profile: store.profile)
                        : _messageList(store, theme),
                  ),
                  if (store.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        "Couldn't reach support. Retrying…",
                        style: TextStyle(color: theme.muted, fontSize: 12),
                      ),
                    ),
                  _composer(store, theme),
                  if (store.branding)
                    _BrandingFooter(
                      theme: theme,
                      onTap: () => unawaited(widget.openUrl(_brandingUrl)),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _messageList(HolloStore store, _ChatTheme theme) {
    final messages = store.messages;
    // Reversed, so the list starts at the newest message and stays there.
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: messages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _pushFooter(store, theme);
        final message = messages[messages.length - index];
        final card = HolloCard.fromMessage(message);
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: card != null
              ? _CardView(
                  card: card,
                  theme: theme,
                  onPressed: () => _pressCard(message, card),
                )
              : message.photos.isNotEmpty
                  ? _PhotoMessage(
                      message: message,
                      theme: theme,
                      teamName: store.profile.name,
                      onOpen: (index) => _openPhotos(message, index),
                    )
                  : _Bubble(
                      message: message,
                      theme: theme,
                      teamName: store.profile.name,
                    ),
        );
      },
    );
  }

  /// Under the user's latest message: the card asking to turn on
  /// notifications (F-40), or a line saying they'll hear about the reply.
  Widget _pushFooter(HolloStore store, _ChatTheme theme) {
    if (store.askPush) {
      final question =
          store.push.permissionCard == HolloPermissionCard.repliesOffers
              ? 'Turn on notifications to hear about replies and offers?'
              : 'Turn on notifications so you know when we reply?';
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _Bordered(
          theme: theme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question,
                style: TextStyle(color: theme.text, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _PillButton(
                      label: 'No thanks',
                      theme: theme,
                      filled: false,
                      onPressed: () => unawaited(store.answerPushCard(false)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PillButton(
                      label: 'Continue',
                      theme: theme,
                      onPressed: () => unawaited(store.answerPushCard(true)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    final waiting = store.messages.isNotEmpty && store.messages.last.fromUser;
    if (waiting && store.pushRegistered && store.push.notifyLine) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            "We'll send you a notification when we reply.",
            style: TextStyle(color: theme.muted, fontSize: 12),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _composer(HolloStore store, _ChatTheme theme) {
    final border = OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      borderSide: BorderSide(color: theme.bubble),
    );
    final canAttach = _photos.length < holloMaxPhotos && !store.sending;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            onPressed: canAttach ? () => unawaited(_attach()) : null,
            padding: EdgeInsets.zero,
            tooltip: 'Attach photos',
            color: theme.text,
            disabledColor: theme.muted,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 24),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: TextField(
            controller: _draft,
            minLines: 1,
            maxLines: 5,
            maxLength: 4000,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            cursorColor: theme.accent,
            style: TextStyle(color: theme.text, fontSize: 15),
            decoration: InputDecoration(
              hintText: _photos.isEmpty ? 'Message' : 'Add a caption',
              hintStyle: TextStyle(color: theme.muted),
              counterText: '',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: BorderSide(color: theme.muted),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _draft,
          builder: (context, value, _) {
            final enabled = (value.text.trim().isNotEmpty ||
                    _photos.isNotEmpty) &&
                !store.sending;
            return Opacity(
              opacity: enabled || store.sending ? 1.0 : 0.35,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Material(
                  color: theme.accent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: enabled ? _send : null,
                    child: Center(
                      child: store.sending
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.onAccent,
                              ),
                            )
                          : Icon(
                              Icons.arrow_upward,
                              size: 20,
                              color: theme.onAccent,
                              semanticLabel: 'Send message',
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PhotoStrip(
                photos: _photos,
                theme: theme,
                onRemove: (index) => setState(() => _photos.removeAt(index)),
              ),
            ),
          row,
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.theme, required this.profile, this.onClose});

  final _ChatTheme theme;
  final HolloProfile profile;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 12),
      child: Row(
        children: [
          _Avatar(photo: profile.photo, theme: theme, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  profile.name ?? theme.title,
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  profile.role ?? 'We usually reply in a few minutes',
                  style: TextStyle(color: theme.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (onClose != null)
            Semantics(
              label: 'Close support chat',
              button: true,
              excludeSemantics: true,
              child: TextButton(
                onPressed: onClose,
                style: TextButton.styleFrom(foregroundColor: theme.text),
                child: const Text(
                  'Done',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Before the first message: who answers and the welcome line.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.theme, required this.profile});

  final _ChatTheme theme;
  final HolloProfile profile;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (profile.photo != null) ...[
              _Avatar(photo: profile.photo, theme: theme, size: 72),
              const SizedBox(height: 12),
            ],
            Text(
              'How can we help?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.text,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              profile.welcome ??
                  "Send us a message and we'll get back to you right here.",
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.muted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// The owner's photo when they've added one, otherwise the Hollo dot.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.photo, required this.theme, required this.size});

  final String? photo;
  final _ChatTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    if (photo != null) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: theme.bubble,
        backgroundImage: NetworkImage(photo),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
      child: Container(
        width: size * 0.39,
        height: size * 0.39,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: theme.onAccent, width: size / 12),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.theme,
    required this.teamName,
  });

  final HolloMessage message;
  final _ChatTheme theme;
  final String? teamName;

  @override
  Widget build(BuildContext context) {
    final mine = message.fromUser;
    final label = switch (message.sender) {
      'ai' => 'AI',
      'team' => teamName,
      _ => null,
    };
    const round = Radius.circular(18);
    const tail = Radius.circular(6);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: mine ? theme.accent : theme.bubble,
            borderRadius: BorderRadius.only(
              topLeft: round,
              topRight: round,
              bottomLeft: mine ? round : tail,
              bottomRight: mine ? tail : round,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      label,
                      style: TextStyle(color: theme.muted, fontSize: 11),
                    ),
                  ),
                Text(
                  message.body,
                  style: TextStyle(
                    color: mine ? theme.onAccent : theme.incomingText,
                    fontSize: 15,
                    height: 1.4,
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

/// The photos chosen for the next message, each with a remove button.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.photos,
    required this.theme,
    required this.onRemove,
  });

  final List<Uint8List> photos;
  final _ChatTheme theme;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    return SizedBox(
      height: size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => Stack(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              child: Image.memory(
                photos[index],
                width: size,
                height: size,
                fit: BoxFit.cover,
                // Decoded small: a full photo per thumbnail wastes memory.
                cacheWidth: 192,
                gaplessPlayback: true,
                semanticLabel:
                    'Photo ${index + 1} of ${photos.length} to send',
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Semantics(
                label: 'Remove photo ${index + 1}',
                button: true,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: () => onRemove(index),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: theme.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close, size: 14, color: theme.onAccent),
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

/// An image message: its photos in a grid, then the caption if it has one.
class _PhotoMessage extends StatelessWidget {
  const _PhotoMessage({
    required this.message,
    required this.theme,
    required this.teamName,
    required this.onOpen,
  });

  final HolloMessage message;
  final _ChatTheme theme;
  final String? teamName;
  final void Function(int index) onOpen;

  @override
  Widget build(BuildContext context) {
    final mine = message.fromUser;
    final photos = message.photos;
    const gap = 4.0;
    final width = min(MediaQuery.sizeOf(context).width * 0.7, 280.0);
    // One photo fills the width; more go two to a row, as squares.
    final tile = photos.length == 1 ? width : (width - gap) / 2;
    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            alignment: mine ? WrapAlignment.end : WrapAlignment.start,
            children: [
              for (var i = 0; i < photos.length; i++)
                Semantics(
                  label: 'Photo ${i + 1} of ${photos.length}',
                  hint: 'Opens full screen',
                  button: true,
                  image: true,
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => onOpen(i),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(14)),
                      child: Container(
                        width: tile,
                        height: photos.length == 1 ? width * 0.75 : tile,
                        color: theme.bubble,
                        child: Image.network(
                          photos[i],
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.broken_image_outlined,
                            color: theme.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (message.body.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _Bubble(message: message, theme: theme, teamName: teamName),
          ),
      ],
    );
  }
}

/// Full screen on black: swipe between the message's photos, pinch or
/// double-tap to zoom.
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.urls, required this.initial});

  final List<String> urls;
  final int initial;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pages =
      PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            // A zoomed photo pans instead of turning the page.
            physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
            itemCount: urls.length,
            onPageChanged: (index) => setState(() {
              _index = index;
              _zoomed = false;
            }),
            itemBuilder: (context, index) => _ZoomablePhoto(
              url: urls[index],
              label: 'Photo ${index + 1} of ${urls.length}',
              onZoomChanged: (zoomed) {
                if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
              },
            ),
          ),
          SafeArea(
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close photo',
                  color: Colors.white,
                  icon: const Icon(Icons.close),
                ),
                const Spacer(),
                if (urls.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      '${_index + 1} / ${urls.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    required this.url,
    required this.label,
    required this.onZoomChanged,
  });

  final String url;
  final String label;
  final void Function(bool zoomed) onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final TransformationController _zoom = TransformationController();
  Offset _tap = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(_changed);
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _changed() {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged(zoomed);
  }

  /// Double tap zooms in on the spot tapped, or back out.
  void _toggle() {
    if (_zoomed) {
      _zoom.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    // Keeps the tapped point where it is: p * scale + t = p.
    _zoom.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(-_tap.dx * (scale - 1), -_tap.dy * (scale - 1), 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _tap = details.localPosition,
      onDoubleTap: _toggle,
      child: InteractiveViewer(
        transformationController: _zoom,
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: Image.network(
            widget.url,
            fit: BoxFit.contain,
            semanticLabel: widget.label,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
            errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white,
              size: 48,
            ),
          ),
        ),
      ),
    );
  }
}

/// A review request, offer or link the team sent, with one button.
class _CardView extends StatelessWidget {
  const _CardView({
    required this.card,
    required this.theme,
    required this.onPressed,
  });

  final HolloCard card;
  final _ChatTheme theme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _Bordered(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (card.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                card.title,
                style: TextStyle(
                  color: theme.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (card.text.isNotEmpty)
            Text(
              card.text,
              style: TextStyle(color: theme.muted, fontSize: 14, height: 1.4),
            ),
          const SizedBox(height: 14),
          _PillButton(label: card.cta, theme: theme, onPressed: onPressed),
        ],
      ),
    );
  }
}

class _Bordered extends StatelessWidget {
  const _Bordered({required this.theme, required this.child});

  final _ChatTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.bubble),
        borderRadius: const BorderRadius.all(Radius.circular(18)),
      ),
      child: child,
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.theme,
    required this.onPressed,
    this.filled = true,
  });

  final String label;
  final _ChatTheme theme;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: filled
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: theme.accent,
                foregroundColor: theme.onAccent,
                shape: const StadiumBorder(),
              ),
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.text,
                side: BorderSide(color: theme.bubble),
                shape: const StadiumBorder(),
              ),
              child: Text(label),
            ),
    );
  }
}

/// "Runs on Hollo" under the composer, unless the server turns it off.
class _BrandingFooter extends StatelessWidget {
  const _BrandingFooter({required this.theme, required this.onTap});

  final _ChatTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        button: true,
        label: 'Runs on Hollo',
        excludeSemantics: true,
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(
                  size: const Size.square(12),
                  painter: _HolloMarkPainter(theme.muted),
                ),
                const SizedBox(width: 5),
                Text(
                  'Runs on Hollo',
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
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

/// The Hollo mark from brand/hollo-mark.svg (48 × 48): a speech bubble with a
/// bubble-shaped hole and a dot, drawn even-odd so the hole stays open.
class _HolloMarkPainter extends CustomPainter {
  const _HolloMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 48;
    final path = Path()..fillType = PathFillType.evenOdd;
    // A disc around (24, 24) whose bottom-left quarter is square.
    for (final r in const [24.0, 13.0]) {
      final lo = (24 - r) * s;
      final hi = (24 + r) * s;
      path
        ..moveTo(lo, 24 * s)
        ..arcTo(Rect.fromLTRB(lo, lo, hi, hi), pi, 3 * pi / 2, false)
        ..lineTo(lo, hi)
        ..close();
    }
    path.addOval(Rect.fromLTRB(18.5 * s, 18.5 * s, 29.5 * s, 29.5 * s));
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HolloMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
