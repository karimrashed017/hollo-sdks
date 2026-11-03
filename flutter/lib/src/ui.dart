import 'dart:async';
import 'dart:math' show pi;

import 'package:flutter/material.dart';

import 'cards.dart';
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

/// Where the "Runs on Hollo" footer goes; ref counts taps from the chat.
final Uri _brandingUrl = Uri.parse('https://hollo.so/?ref=chat');

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
    this.onClose,
  });

  final HolloStore store;
  final HolloTheme theme;

  /// `ios`, `android` or `web`: picks the store page for review cards.
  final String os;
  final void Function(HolloOffer offer) onOffer;
  final void Function(HolloMessage message) onLink;
  final Future<bool> Function(Uri uri) openUrl;

  /// Shows a Done button when set (the presented chat).
  final VoidCallback? onClose;

  @override
  State<HolloChatView> createState() => _HolloChatViewState();
}

class _HolloChatViewState extends State<HolloChatView> {
  final TextEditingController _draft = TextEditingController();
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
    if (text.trim().isEmpty || widget.store.sending) return;
    _draft.clear();
    try {
      await widget.store.send(text);
    } catch (_) {
      // Put it back so the user can try again.
      if (mounted && _draft.text.isEmpty) _draft.text = text;
    }
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
    final theme = widget.theme;
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final store = widget.store;
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

  Widget _messageList(HolloStore store, HolloTheme theme) {
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
          child: card == null
              ? _Bubble(
                  message: message,
                  theme: theme,
                  teamName: store.profile.name,
                )
              : _CardView(
                  card: card,
                  theme: theme,
                  onPressed: () => _pressCard(message, card),
                ),
        );
      },
    );
  }

  /// Under the user's latest message: the card asking to turn on
  /// notifications (F-40), or a line saying they'll hear about the reply.
  Widget _pushFooter(HolloStore store, HolloTheme theme) {
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

  Widget _composer(HolloStore store, HolloTheme theme) {
    final border = OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      borderSide: BorderSide(color: theme.bubble),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
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
                hintText: 'Message',
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
              final enabled = value.text.trim().isNotEmpty && !store.sending;
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
                                  color: theme.background,
                                ),
                              )
                            : Icon(
                                Icons.arrow_upward,
                                size: 20,
                                color: theme.background,
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
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.theme, required this.profile, this.onClose});

  final HolloTheme theme;
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

  final HolloTheme theme;
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
  final HolloTheme theme;
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
          border: Border.all(color: theme.background, width: size / 12),
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
  final HolloTheme theme;
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
                    color: mine ? theme.background : theme.text,
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

/// A review request, offer or link the team sent, with one button.
class _CardView extends StatelessWidget {
  const _CardView({
    required this.card,
    required this.theme,
    required this.onPressed,
  });

  final HolloCard card;
  final HolloTheme theme;
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

  final HolloTheme theme;
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
  final HolloTheme theme;
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
                foregroundColor: theme.background,
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

  final HolloTheme theme;
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
