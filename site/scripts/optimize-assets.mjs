import sharp from "sharp";
import { fileURLToPath } from "node:url";

const pathFromHere = (path) => fileURLToPath(new URL(path, import.meta.url));
const iconSource = pathFromHere("../public/fanbar-icon.png");
const heroSource = pathFromHere("../public/screenshots/fanbar-menu-rounded-clean.png");

await Promise.all([
  sharp(iconSource)
    .resize(64, 64)
    .webp({ quality: 88, effort: 6 })
    .toFile(pathFromHere("../public/fanbar-icon-64.webp")),
  sharp(iconSource)
    .resize(64, 64)
    .png({ compressionLevel: 9, palette: true })
    .toFile(pathFromHere("../public/fanbar-icon-64.png")),
  sharp(iconSource)
    .resize(180, 180)
    .png({ compressionLevel: 9, palette: true })
    .toFile(pathFromHere("../public/apple-touch-icon.png")),
  sharp(iconSource)
    .resize(192, 192)
    .png({ compressionLevel: 9, palette: true })
    .toFile(pathFromHere("../public/icon-192.png")),
  sharp(iconSource)
    .resize(512, 512)
    .png({ compressionLevel: 9, palette: true })
    .toFile(pathFromHere("../public/icon-512.png")),
  ...[386, 772].flatMap((width) => [
    sharp(heroSource)
      .resize({ width, withoutEnlargement: true })
      .avif({ quality: 62, effort: 6 })
      .toFile(pathFromHere(`../public/screenshots/fanbar-menu-rounded-${width}.avif`)),
    sharp(heroSource)
      .resize({ width, withoutEnlargement: true })
      .webp({ quality: 82, effort: 6 })
      .toFile(pathFromHere(`../public/screenshots/fanbar-menu-rounded-${width}.webp`)),
  ]),
]);
