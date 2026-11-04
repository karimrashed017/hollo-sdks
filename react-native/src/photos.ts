import { MAX_PHOTOS } from "./client";

// Picking and compressing photos (F-17) with expo-image-picker and
// expo-image-manipulator. Both are optional: without them the chat has no
// attach button. They're required inside try/catch, which Metro treats as
// optional dependencies, so apps that skip them still build.

/** A picked photo, already a JPEG on the device. */
export type PhotoDraft = { uri: string; width: number; height: number };

/** Long edge of what we upload: sharp enough to read a screenshot. */
const LONG_EDGE = 1600;
const QUALITY = 0.7;

type Picker = typeof import("expo-image-picker");
type Manipulator = typeof import("expo-image-manipulator");

function load(): { picker: Picker; manipulator: Manipulator } | null {
  try {
    /* eslint-disable @typescript-eslint/no-require-imports */
    const picker = require("expo-image-picker") as Picker;
    const manipulator = require("expo-image-manipulator") as Manipulator;
    /* eslint-enable @typescript-eslint/no-require-imports */
    return typeof picker?.launchImageLibraryAsync === "function" &&
      typeof manipulator?.ImageManipulator?.manipulate === "function"
      ? { picker, manipulator }
      : null;
  } catch {
    return null;
  }
}

const modules = load();

/** Whether the app installed the two Expo modules photos need. */
export const canAttachPhotos = modules !== null;

/**
 * Opens the system photo picker (no permission needed) for up to `limit`
 * photos and returns them as compressed JPEGs, or [] when cancelled.
 */
export async function pickPhotos(limit = MAX_PHOTOS): Promise<PhotoDraft[]> {
  if (!modules || limit < 1) return [];
  const { picker, manipulator } = modules;
  const result = await picker.launchImageLibraryAsync({
    mediaTypes: ["images"],
    allowsMultipleSelection: limit > 1,
    selectionLimit: limit,
    quality: 1,
  });
  if (result.canceled) return [];
  return Promise.all(
    result.assets.slice(0, limit).map(async (asset) => {
      // Also turns HEIC into JPEG, which the server needs.
      const context = manipulator.ImageManipulator.manipulate(asset.uri);
      if (Math.max(asset.width, asset.height) > LONG_EDGE) {
        context.resize(
          asset.width >= asset.height
            ? { width: LONG_EDGE }
            : { height: LONG_EDGE },
        );
      }
      const image = await context.renderAsync();
      const saved = await image.saveAsync({
        compress: QUALITY,
        format: manipulator.SaveFormat.JPEG,
      });
      return { uri: saved.uri, width: saved.width, height: saved.height };
    }),
  );
}

/** The JPEG's bytes, for the upload. Works for file, blob and data URIs. */
export async function photoBlob(uri: string) {
  const response = await fetch(uri);
  return response.blob();
}
