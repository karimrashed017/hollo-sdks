import { useEffect, useMemo, useRef, useState, type ComponentRef } from "react";
import {
  Animated,
  Image,
  Modal,
  PanResponder,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
  useWindowDimensions,
  type GestureResponderEvent,
} from "react-native";
import type { ChatColors } from "./theme";

// Photos in the chat (F-17): the thumbnails in a message, and the full-screen
// viewer with pinch and double-tap zoom. Built on PanResponder, so there's no
// gesture library to install.

/** A message's photos: one large, or a two-column grid. */
export function PhotoMessage({
  urls,
  theme,
  onOpen,
}: {
  urls: string[];
  theme: ChatColors;
  onOpen: (index: number) => void;
}) {
  if (!urls.length) {
    return (
      <Text style={{ color: theme.muted, fontSize: 13, padding: 8 }}>
        Photo unavailable
      </Text>
    );
  }
  const one = urls.length === 1;
  return (
    <View style={styles.grid}>
      {urls.map((url, i) => (
        <Pressable
          key={url}
          onPress={() => onOpen(i)}
          accessibilityRole="imagebutton"
          accessibilityLabel={`Photo ${i + 1} of ${urls.length}. Opens full screen.`}
        >
          <Image
            source={{ uri: url }}
            style={[
              one ? styles.single : styles.tile,
              { backgroundColor: theme.bubble },
            ]}
            resizeMode="cover"
            accessibilityIgnoresInvertColors
          />
        </Pressable>
      ))}
    </View>
  );
}

/** Full screen, black, swipe between photos; pinch or double-tap to zoom. */
export function PhotoViewer({
  urls,
  index,
  visible,
  onClose,
}: {
  urls: string[];
  index: number;
  visible: boolean;
  onClose: () => void;
}) {
  const { width, height } = useWindowDimensions();
  const pager = useRef<ComponentRef<typeof ScrollView>>(null);
  const [page, setPage] = useState(index);
  const [zoomed, setZoomed] = useState(false);

  useEffect(() => {
    if (!visible) return;
    setPage(index);
    // After the modal lays out, jump to the photo that was tapped.
    const t = setTimeout(
      () => pager.current?.scrollTo({ x: index * width, animated: false }),
      0,
    );
    return () => clearTimeout(t);
  }, [visible, index, width]);

  return (
    <Modal
      visible={visible}
      animationType="fade"
      onRequestClose={onClose}
      supportedOrientations={["portrait", "landscape"]}
    >
      <View style={styles.viewer}>
        <ScrollView
          ref={pager}
          horizontal
          pagingEnabled
          scrollEnabled={!zoomed}
          showsHorizontalScrollIndicator={false}
          onMomentumScrollEnd={(e) =>
            setPage(Math.round(e.nativeEvent.contentOffset.x / width))
          }
        >
          {urls.map((url, i) => (
            <ZoomableImage
              key={url}
              url={url}
              width={width}
              height={height}
              label={`Photo ${i + 1} of ${urls.length}`}
              onZoom={setZoomed}
            />
          ))}
        </ScrollView>
        <View style={styles.bar} pointerEvents="box-none">
          {urls.length > 1 ? (
            <Text style={styles.counter}>
              {page + 1} / {urls.length}
            </Text>
          ) : (
            <View />
          )}
          <Pressable
            onPress={onClose}
            accessibilityRole="button"
            accessibilityLabel="Close photo"
            hitSlop={12}
            style={styles.closeButton}
          >
            <Text style={styles.closeText}>✕</Text>
          </Pressable>
        </View>
      </View>
    </Modal>
  );
}

const MAX_SCALE = 4;
const DOUBLE_TAP_MS = 280;

function distance(e: GestureResponderEvent) {
  const [a, b] = e.nativeEvent.touches;
  return Math.hypot(a.pageX - b.pageX, a.pageY - b.pageY);
}

function ZoomableImage({
  url,
  width,
  height,
  label,
  onZoom,
}: {
  url: string;
  width: number;
  height: number;
  label: string;
  onZoom: (zoomed: boolean) => void;
}) {
  const scale = useRef(new Animated.Value(1)).current;
  const x = useRef(new Animated.Value(0)).current;
  const y = useRef(new Animated.Value(0)).current;
  // The values as of the last gesture's end, plus the gesture's start.
  const g = useRef({ scale: 1, x: 0, y: 0, pinch: 0, lastTap: 0 }).current;

  const responder = useMemo(() => {
    const set = (s: number, nx: number, ny: number) => {
      // Keep the photo on screen: it can move only as far as it's zoomed.
      const maxX = ((s - 1) * width) / 2;
      const maxY = ((s - 1) * height) / 2;
      const cx = Math.max(-maxX, Math.min(maxX, nx));
      const cy = Math.max(-maxY, Math.min(maxY, ny));
      scale.setValue(s);
      x.setValue(cx);
      y.setValue(cy);
      return { s, cx, cy };
    };
    let live = { s: 1, cx: 0, cy: 0 };
    const commit = () => {
      g.scale = live.s;
      g.x = live.cx;
      g.y = live.cy;
      onZoom(g.scale > 1.01);
    };
    return PanResponder.create({
      // Two fingers always zoom; one finger only pans a zoomed photo, so
      // swiping still moves between photos.
      onStartShouldSetPanResponder: (e) =>
        e.nativeEvent.touches.length === 2 || g.scale > 1.01,
      onMoveShouldSetPanResponder: (e) =>
        e.nativeEvent.touches.length === 2 || g.scale > 1.01,
      onPanResponderGrant: (e) => {
        g.pinch = e.nativeEvent.touches.length === 2 ? distance(e) : 0;
      },
      onPanResponderMove: (e, state) => {
        if (e.nativeEvent.touches.length === 2) {
          if (!g.pinch) g.pinch = distance(e);
          const s = Math.max(
            1,
            Math.min(MAX_SCALE, (g.scale * distance(e)) / g.pinch),
          );
          live = set(s, g.x, g.y);
        } else if (g.scale > 1.01) {
          live = set(g.scale, g.x + state.dx, g.y + state.dy);
        }
      },
      onPanResponderRelease: commit,
      onPanResponderTerminate: commit,
    });
  }, [g, height, onZoom, scale, width, x, y]);

  // Double tap zooms in to 2x, or back out.
  function tap() {
    const now = Date.now();
    if (now - g.lastTap < DOUBLE_TAP_MS) {
      const s = g.scale > 1.01 ? 1 : 2;
      g.scale = s;
      g.x = 0;
      g.y = 0;
      Animated.parallel([
        Animated.spring(scale, { toValue: s, useNativeDriver: true }),
        Animated.spring(x, { toValue: 0, useNativeDriver: true }),
        Animated.spring(y, { toValue: 0, useNativeDriver: true }),
      ]).start();
      onZoom(s > 1);
      g.lastTap = 0;
    } else {
      g.lastTap = now;
    }
  }

  return (
    <View style={{ width, height }} {...responder.panHandlers}>
      <Pressable onPress={tap} style={StyleSheet.absoluteFill}>
        <Animated.Image
          source={{ uri: url }}
          resizeMode="contain"
          accessibilityLabel={label}
          accessibilityIgnoresInvertColors
          style={{
            width,
            height,
            transform: [{ translateX: x }, { translateY: y }, { scale }],
          }}
        />
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  grid: { flexDirection: "row", flexWrap: "wrap", gap: 4, maxWidth: 228 },
  single: { width: 228, height: 228, borderRadius: 14 },
  tile: { width: 112, height: 112, borderRadius: 12 },
  viewer: { flex: 1, backgroundColor: "#000000" },
  bar: {
    position: "absolute",
    top: 0,
    left: 0,
    right: 0,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingTop: 52,
    paddingHorizontal: 20,
  },
  counter: { color: "#FFFFFF", fontSize: 14, fontWeight: "600" },
  closeButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: "rgba(255,255,255,0.18)",
    alignItems: "center",
    justifyContent: "center",
  },
  closeText: { color: "#FFFFFF", fontSize: 16 },
});
