import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import {
  ActivityIndicator,
  FlatList,
  ScrollView,
  Image,
  KeyboardAvoidingView,
  Linking,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { MAX_PHOTOS, type HolloMessage, type HolloOffer } from "./client";
import { reviewUrl } from "./links";
import { PhotoMessage, PhotoViewer } from "./photo-viewer";
import {
  canAttachPhotos,
  photoBlob,
  pickPhotos,
  type PhotoDraft,
} from "./photos";
import type { HolloState, HolloStore } from "./store";
import { chatColors, type ChatColors, type HolloTheme } from "./theme";

// The native chat screen. Black and white by default; pass a theme to match
// the host app. Colours set in the dashboard go over it.

export { defaultTheme, type HolloTheme } from "./theme";

export function useStore(store: HolloStore) {
  return useSyncExternalStore(store.subscribe, store.getState, store.getState);
}

export function HolloChat({
  store,
  theme: localTheme,
  onClose,
  onOffer,
  onLink,
}: {
  store: HolloStore;
  theme?: Partial<HolloTheme>;
  onClose?: () => void;
  onOffer?: (offer: HolloOffer) => void;
  onLink?: (message: HolloMessage) => void;
}) {
  const state = useStore(store);
  const theme = chatColors(localTheme, state.remoteTheme);
  const profile = state.profile;
  const [draft, setDraft] = useState("");
  const [photos, setPhotos] = useState<PhotoDraft[]>([]);
  const [viewing, setViewing] = useState<{
    urls: string[];
    index: number;
  } | null>(null);
  const list = useRef<FlatList<HolloMessage>>(null);
  const canSend = (!!draft.trim() || photos.length > 0) && !state.sending;

  // Embedded chats count as open while they're on screen.
  useEffect(() => {
    if (onClose) return;
    store.setOpen(true);
    return () => store.setOpen(false);
  }, [store, onClose]);

  async function send() {
    const text = draft;
    const attached = photos;
    setDraft("");
    setPhotos([]);
    try {
      await store.send(text, attached, (photo) => photoBlob(photo.uri));
    } catch {
      // Keep the draft, photos too, so they can send it again.
      setDraft(text);
      setPhotos(attached);
    }
  }

  async function attach() {
    try {
      const picked = await pickPhotos(MAX_PHOTOS - photos.length);
      if (picked.length)
        setPhotos((p) => [...p, ...picked].slice(0, MAX_PHOTOS));
    } catch {
      // The picker failed or was refused: nothing to attach.
    }
  }

  return (
    <KeyboardAvoidingView
      style={[styles.screen, { backgroundColor: theme.background }]}
      behavior={Platform.OS === "ios" ? "padding" : undefined}
    >
      <View style={styles.header}>
        <Avatar photo={profile.photo} theme={theme} size={36} />
        <View style={{ flex: 1 }}>
          <Text style={[styles.title, { color: theme.text }]}>
            {profile.name ?? theme.title}
          </Text>
          <Text style={[styles.subtitle, { color: theme.muted }]}>
            {profile.role ?? "We usually reply in a few minutes"}
          </Text>
        </View>
        {onClose && (
          <Pressable
            onPress={onClose}
            accessibilityRole="button"
            accessibilityLabel="Close support chat"
            hitSlop={12}
          >
            <Text style={[styles.close, { color: theme.text }]}>Done</Text>
          </Pressable>
        )}
      </View>

      <FlatList
        ref={list}
        data={state.messages}
        keyExtractor={(m) => m.id}
        contentContainerStyle={styles.messages}
        onContentSizeChange={() =>
          list.current?.scrollToEnd({ animated: true })
        }
        ListFooterComponent={
          <PushFooter store={store} state={state} theme={theme} />
        }
        ListEmptyComponent={
          <View style={styles.empty}>
            {profile.photo && (
              <Avatar photo={profile.photo} theme={theme} size={72} />
            )}
            <Text style={[styles.emptyTitle, { color: theme.text }]}>
              How can we help?
            </Text>
            <Text style={[styles.emptyText, { color: theme.muted }]}>
              {profile.welcome ??
                "Send us a message and we'll get back to you right here."}
            </Text>
          </View>
        }
        renderItem={({ item }) => {
          if (
            item.kind === "review_request" ||
            item.kind === "offer" ||
            item.kind === "link"
          ) {
            return (
              <Card
                message={item}
                theme={theme}
                onOffer={onOffer}
                onLink={onLink}
              />
            );
          }
          const mine = item.sender === "end_user";
          return (
            <View
              style={[
                styles.bubble,
                item.kind === "image" && styles.photoBubble,
                mine
                  ? [styles.mine, { backgroundColor: theme.accent }]
                  : [styles.theirs, { backgroundColor: theme.bubble }],
              ]}
            >
              {item.sender === "ai" && (
                <Text style={[styles.label, { color: theme.muted }]}>AI</Text>
              )}
              {item.sender === "team" && profile.name && (
                <Text style={[styles.label, { color: theme.muted }]}>
                  {profile.name}
                </Text>
              )}
              {item.kind === "image" && (
                <PhotoMessage
                  urls={item.photos ?? []}
                  theme={theme}
                  onOpen={(index) =>
                    setViewing({ urls: item.photos ?? [], index })
                  }
                />
              )}
              {!!item.body && (
                <Text
                  style={{
                    color: mine ? theme.onAccent : theme.incomingText,
                    fontSize: 15,
                    lineHeight: 21,
                    ...(item.kind === "image" && {
                      paddingHorizontal: 10,
                      paddingTop: 4,
                      paddingBottom: 4,
                    }),
                  }}
                >
                  {item.body}
                </Text>
              )}
            </View>
          );
        }}
      />

      {state.error && (
        <Text style={[styles.error, { color: theme.muted }]}>
          Couldn&apos;t reach support. Retrying…
        </Text>
      )}

      {photos.length > 0 && (
        <ScrollView
          horizontal
          style={styles.drafts}
          contentContainerStyle={styles.draftsContent}
          keyboardShouldPersistTaps="handled"
        >
          {photos.map((photo, i) => (
            <View key={photo.uri}>
              <Image
                source={{ uri: photo.uri }}
                style={[styles.draft, { backgroundColor: theme.bubble }]}
                accessibilityLabel={`Photo ${i + 1} to send`}
              />
              <Pressable
                onPress={() =>
                  setPhotos((p) => p.filter((x) => x.uri !== photo.uri))
                }
                accessibilityRole="button"
                accessibilityLabel={`Remove photo ${i + 1}`}
                hitSlop={8}
                style={[styles.removeDraft, { backgroundColor: theme.text }]}
              >
                <Text style={{ color: theme.background, fontSize: 12 }}>✕</Text>
              </Pressable>
            </View>
          ))}
        </ScrollView>
      )}

      <View
        style={[
          styles.composer,
          // The footer takes over the bottom inset when it shows.
          state.branding && { paddingBottom: 8 },
        ]}
      >
        {canAttachPhotos && (
          <Pressable
            onPress={() => void attach()}
            disabled={photos.length >= MAX_PHOTOS || state.sending}
            accessibilityRole="button"
            accessibilityLabel="Attach photos"
            style={[
              styles.attach,
              {
                borderColor: theme.bubble,
                opacity: photos.length >= MAX_PHOTOS ? 0.35 : 1,
              },
            ]}
          >
            <PhotoIcon color={theme.text} />
          </Pressable>
        )}
        <TextInput
          value={draft}
          onChangeText={setDraft}
          placeholder="Message"
          placeholderTextColor={theme.muted}
          multiline
          maxLength={4000}
          style={[
            styles.input,
            { color: theme.text, borderColor: theme.bubble },
          ]}
          accessibilityLabel="Message"
        />
        <Pressable
          onPress={send}
          disabled={!canSend}
          accessibilityRole="button"
          accessibilityLabel="Send message"
          style={[
            styles.send,
            {
              backgroundColor: theme.accent,
              opacity: canSend ? 1 : 0.35,
            },
          ]}
        >
          {state.sending ? (
            <ActivityIndicator color={theme.onAccent} size="small" />
          ) : (
            <Text style={{ color: theme.onAccent, fontSize: 17 }}>↑</Text>
          )}
        </Pressable>
      </View>

      {state.branding && <BrandingFooter theme={theme} />}
      <PhotoViewer
        urls={viewing?.urls ?? []}
        index={viewing?.index ?? 0}
        visible={!!viewing}
        onClose={() => setViewing(null)}
      />
    </KeyboardAvoidingView>
  );
}

/** A review request, offer or link the team sent, with one button. */
/**
 * Under the user's latest message: the card asking to turn on notifications
 * (F-40), or a line saying they'll be notified of the reply (F-16).
 */
function PushFooter({
  store,
  state,
  theme,
}: {
  store: HolloStore;
  state: HolloState;
  theme: ChatColors;
}) {
  const waiting = state.messages.at(-1)?.sender === "end_user";
  if (state.askPush) {
    return (
      <View style={[styles.card, { borderColor: theme.bubble }]}>
        <Text style={[styles.cardText, { color: theme.text }]}>
          {state.push.permissionCard === "replies_offers"
            ? "Turn on notifications to hear about replies and offers?"
            : "Turn on notifications so you know when we reply?"}
        </Text>
        <View style={styles.cardActions}>
          <Pressable
            onPress={() => void store.answerPushCard(false)}
            accessibilityRole="button"
            style={[
              styles.cardButton,
              styles.cardButtonHalf,
              { borderColor: theme.bubble, borderWidth: 1 },
            ]}
          >
            <Text style={{ color: theme.text }}>No thanks</Text>
          </Pressable>
          <Pressable
            onPress={() => void store.answerPushCard(true)}
            accessibilityRole="button"
            style={[
              styles.cardButton,
              styles.cardButtonHalf,
              { backgroundColor: theme.accent },
            ]}
          >
            <Text style={{ color: theme.onAccent, fontWeight: "600" }}>
              Continue
            </Text>
          </Pressable>
        </View>
      </View>
    );
  }
  if (waiting && state.pushRegistered && state.push.notifyLine) {
    return (
      <Text style={[styles.notifyLine, { color: theme.muted }]}>
        {"We'll send you a notification when we reply."}
      </Text>
    );
  }
  return null;
}

/** A small picture icon in Views, so there's no icon dependency. */
function PhotoIcon({ color }: { color: string }) {
  return (
    <View style={[styles.photoIcon, { borderColor: color }]}>
      <View style={[styles.photoIconSun, { backgroundColor: color }]} />
      <View style={[styles.photoIconHill, { borderBottomColor: color }]} />
    </View>
  );
}

/** The owner's photo when they've added one, otherwise the Hollo dot. */
function Avatar({
  photo,
  theme,
  size,
}: {
  photo?: string;
  theme: ChatColors;
  size: number;
}) {
  const round = { width: size, height: size, borderRadius: size / 2 };
  if (photo) {
    return (
      <Image
        source={{ uri: photo }}
        style={[round, { backgroundColor: theme.bubble }]}
        accessibilityIgnoresInvertColors
      />
    );
  }
  return (
    <View style={[styles.avatar, round, { backgroundColor: theme.accent }]}>
      <View style={[styles.avatarDot, { borderColor: theme.avatarRing }]} />
    </View>
  );
}

const BRANDING_URL = "https://hollo.so/?ref=chat";

/** "Runs on Hollo" under the composer, unless the server turns it off. */
function BrandingFooter({ theme }: { theme: HolloTheme }) {
  return (
    <Pressable
      onPress={() => void Linking.openURL(BRANDING_URL).catch(() => {})}
      accessibilityRole="link"
      accessibilityLabel="Runs on Hollo"
      style={styles.branding}
    >
      <HolloMark color={theme.muted} hole={theme.background} size={12} />
      <Text style={[styles.brandingText, { color: theme.muted }]}>
        Runs on Hollo
      </Text>
    </Pressable>
  );
}

/**
 * The Hollo mark from brand/hollo-mark.svg, in Views so there's no SVG
 * dependency: a bubble (square bottom-left corner) with a bubble-shaped hole
 * painted in the background colour, and a dot in the middle.
 */
function HolloMark({
  color,
  hole,
  size,
}: {
  color: string;
  hole: string;
  size: number;
}) {
  const bubble = (d: number, fill: string) => ({
    width: d,
    height: d,
    borderRadius: d / 2,
    borderBottomLeftRadius: 0,
    backgroundColor: fill,
    alignItems: "center" as const,
    justifyContent: "center" as const,
  });
  const dot = (size * 11) / 48;
  return (
    <View style={bubble(size, color)}>
      <View style={bubble((size * 26) / 48, hole)}>
        <View
          style={{
            width: dot,
            height: dot,
            borderRadius: dot / 2,
            backgroundColor: color,
          }}
        />
      </View>
    </View>
  );
}

function Card({
  message,
  theme,
  onOffer,
  onLink,
}: {
  message: HolloMessage;
  theme: ChatColors;
  onOffer?: (offer: HolloOffer) => void;
  onLink?: (message: HolloMessage) => void;
}) {
  const p = message.payload ?? {};
  const str = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const review = message.kind === "review_request";
  const link = message.kind === "link";
  // Review requests carry the team's wording in the user's language.
  const title = review ? "" : link ? "" : str("title");
  const text = review
    ? message.body || "Enjoying the app? A quick review helps us a lot."
    : link
      ? message.body
      : str("description");
  const cta = review
    ? str("cta") || "Leave a review"
    : link
      ? str("label") || "Open"
      : str("cta") || "See offer";

  function press() {
    if (review) {
      const url = reviewUrl(Platform.OS, p);
      if (url) void Linking.openURL(url).catch(() => {});
    } else if (link) {
      onLink?.(message);
    } else {
      onOffer?.({ ref: str("ref"), title: str("title") });
    }
  }

  return (
    <View style={[styles.card, { borderColor: theme.bubble }]}>
      {!!title && (
        <Text style={[styles.cardTitle, { color: theme.text }]}>{title}</Text>
      )}
      {!!text && (
        <Text style={[styles.cardText, { color: theme.muted }]}>{text}</Text>
      )}
      <Pressable
        onPress={press}
        accessibilityRole="button"
        style={[styles.cardButton, { backgroundColor: theme.accent }]}
      >
        <Text style={{ color: theme.onAccent, fontWeight: "600" }}>{cta}</Text>
      </Pressable>
    </View>
  );
}

/** Hosts the chat sheet that Hollo.present() opens. */
export function HolloSheet({
  store,
  theme,
  onOffer,
  onLink,
}: {
  store: HolloStore;
  theme?: Partial<HolloTheme>;
  onOffer?: (offer: HolloOffer) => void;
  onLink?: (message: HolloMessage) => void;
}) {
  const { open } = useStore(store);
  return (
    <Modal
      visible={open}
      animationType="slide"
      presentationStyle="pageSheet"
      onRequestClose={() => store.setOpen(false)}
    >
      <HolloChat
        store={store}
        theme={theme}
        onOffer={onOffer}
        onLink={onLink}
        onClose={() => store.setOpen(false)}
      />
    </Modal>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  header: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 14,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: "#E5E5E3",
  },
  avatar: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: "center",
    justifyContent: "center",
  },
  avatarDot: {
    width: 14,
    height: 14,
    borderRadius: 7,
    borderWidth: 3,
  },
  title: { fontSize: 16, fontWeight: "600" },
  subtitle: { fontSize: 12, marginTop: 1 },
  close: { fontSize: 16, fontWeight: "600" },
  messages: { padding: 16, gap: 8, flexGrow: 1 },
  empty: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    padding: 32,
  },
  emptyTitle: { fontSize: 20, fontWeight: "600", marginTop: 12 },
  emptyText: { fontSize: 14, marginTop: 6, textAlign: "center" },
  bubble: {
    maxWidth: "80%",
    paddingHorizontal: 14,
    paddingVertical: 9,
    borderRadius: 18,
  },
  mine: { alignSelf: "flex-end", borderBottomRightRadius: 6 },
  theirs: { alignSelf: "flex-start", borderBottomLeftRadius: 6 },
  label: { fontSize: 11, marginBottom: 2 },
  card: {
    alignSelf: "stretch",
    borderWidth: 1,
    borderRadius: 18,
    padding: 16,
    gap: 6,
  },
  cardTitle: { fontSize: 16, fontWeight: "600" },
  cardText: { fontSize: 14, lineHeight: 20 },
  cardButton: {
    marginTop: 8,
    height: 40,
    borderRadius: 20,
    alignItems: "center",
    justifyContent: "center",
  },
  cardActions: { flexDirection: "row", gap: 8 },
  cardButtonHalf: { flex: 1 },
  notifyLine: { alignSelf: "flex-end", fontSize: 12, marginTop: 2 },
  error: { textAlign: "center", fontSize: 12, paddingBottom: 4 },
  composer: {
    flexDirection: "row",
    alignItems: "flex-end",
    gap: 8,
    padding: 12,
    paddingBottom: Platform.OS === "ios" ? 28 : 12,
  },
  input: {
    flex: 1,
    minHeight: 40,
    maxHeight: 120,
    borderWidth: 1,
    borderRadius: 20,
    paddingHorizontal: 16,
    paddingVertical: 10,
    fontSize: 15,
  },
  branding: {
    flexDirection: "row",
    alignItems: "center",
    alignSelf: "center",
    gap: 5,
    paddingHorizontal: 8,
    paddingTop: 2,
    paddingBottom: Platform.OS === "ios" ? 24 : 8,
  },
  brandingText: { fontSize: 11, fontWeight: "500" },
  attach: {
    width: 40,
    height: 40,
    borderRadius: 20,
    borderWidth: 1,
    alignItems: "center",
    justifyContent: "center",
  },
  photoIcon: {
    width: 20,
    height: 16,
    borderWidth: 1.5,
    borderRadius: 3,
    overflow: "hidden",
  },
  photoIconSun: {
    position: "absolute",
    top: 2,
    right: 3,
    width: 4,
    height: 4,
    borderRadius: 2,
  },
  photoIconHill: {
    position: "absolute",
    bottom: -1,
    left: 1,
    width: 0,
    height: 0,
    borderLeftWidth: 6,
    borderRightWidth: 6,
    borderBottomWidth: 8,
    borderLeftColor: "transparent",
    borderRightColor: "transparent",
  },
  photoBubble: { padding: 4, paddingBottom: 4 },
  drafts: { flexGrow: 0 },
  draftsContent: { gap: 8, paddingHorizontal: 12, paddingTop: 8 },
  draft: { width: 56, height: 56, borderRadius: 10 },
  removeDraft: {
    position: "absolute",
    top: -4,
    right: -4,
    width: 20,
    height: 20,
    borderRadius: 10,
    alignItems: "center",
    justifyContent: "center",
  },
  send: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: "center",
    justifyContent: "center",
  },
});
