import fs from "node:fs";
import path from "node:path";

const [, , iconsetPath, outputPath] = process.argv;
if (!iconsetPath || !outputPath) {
  throw new Error("Usage: node make-icns.mjs <iconset> <output.icns>");
}

// Modern ICNS records store complete PNG payloads behind four-byte type codes.
const records = [
  ["icp4", "icon_16x16.png"],
  ["icp5", "icon_32x32.png"],
  ["icp6", "icon_32x32@2x.png"],
  ["ic07", "icon_128x128.png"],
  ["ic08", "icon_256x256.png"],
  ["ic09", "icon_512x512.png"],
  ["ic10", "icon_512x512@2x.png"],
  ["ic11", "icon_16x16@2x.png"],
  ["ic12", "icon_32x32@2x.png"],
  ["ic13", "icon_128x128@2x.png"],
  ["ic14", "icon_256x256@2x.png"],
].map(([type, filename]) => {
  const payload = fs.readFileSync(path.join(iconsetPath, filename));
  const record = Buffer.alloc(8 + payload.length);
  record.write(type, 0, 4, "ascii");
  record.writeUInt32BE(record.length, 4);
  payload.copy(record, 8);
  return record;
});

const totalLength = 8 + records.reduce((total, record) => total + record.length, 0);
const header = Buffer.alloc(8);
header.write("icns", 0, 4, "ascii");
header.writeUInt32BE(totalLength, 4);
fs.writeFileSync(outputPath, Buffer.concat([header, ...records], totalLength));
