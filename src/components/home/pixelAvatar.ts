import { pixelArt } from "@dicebear/collection";
import { createAvatar } from "@dicebear/core";

const avatarCache = new Map<string, string>();

export function getPixelAvatarDataUri(seed: string) {
  const cached = avatarCache.get(seed);

  if (cached) {
    return cached;
  }

  const dataUri = createAvatar(pixelArt, {
    seed,
    backgroundColor: ["transparent"],
    scale: 92,
  }).toDataUri();

  avatarCache.set(seed, dataUri);

  return dataUri;
}
