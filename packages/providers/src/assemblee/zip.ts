import { Unzip, UnzipInflate } from "fflate";

// Parcourt une archive fichier par fichier sans tout décompresser d'un coup : les scrutins pèsent plus de 200 Mo une
// fois dézippés, le worker du NAS a une mémoire limitée.
export function eachZipEntry(zip: Uint8Array, onFile: (name: string, data: Uint8Array) => void): void {
  const unzip = new Unzip((file) => {
    if (file.name.endsWith("/")) return;
    const chunks: Uint8Array[] = [];
    file.ondata = (err, chunk, final) => {
      if (err) throw err;
      chunks.push(chunk);
      if (final) onFile(file.name, Buffer.concat(chunks));
    };
    file.start();
  });
  unzip.register(UnzipInflate);
  // Par morceaux : fflate empile un appel par fichier d'un même morceau, des milliers de petits fichiers d'un coup
  // débordent la pile.
  const CHUNK = 64 * 1024;
  for (let i = 0; i < zip.length; i += CHUNK) unzip.push(zip.subarray(i, i + CHUNK), i + CHUNK >= zip.length);
}

export function eachZipJson(zip: Uint8Array, onJson: (name: string, json: unknown) => void): void {
  eachZipEntry(zip, (name, data) => {
    if (!name.endsWith(".json")) return;
    onJson(name, JSON.parse(Buffer.from(data).toString("utf8").replace(/^﻿/, "")));
  });
}
