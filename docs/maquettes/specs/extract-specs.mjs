// Outil de mesure : extrait rects/paths/textes des SVG exportés par Figma
// (export avec "Outline text" décoché : vrais éléments <text>/<tspan> avec
// police, taille, graisse, tracking, couleur, position de ligne de base).
// Usage :
//   node docs/maquettes/specs/extract-specs.mjs docs/maquettes/svg/17-accueil.svg

import { readFileSync } from "node:fs";

function parseAttrs(attrStr) {
  const attrs = {};
  const re = /([\w:-]+)\s*=\s*"([^"]*)"/g;
  let m;
  while ((m = re.exec(attrStr))) attrs[m[1]] = m[2];
  return attrs;
}

function stripBlocks(svg, tag) {
  return svg.replace(new RegExp(`<${tag}[^>]*>[\\s\\S]*?</${tag}>`, "g"), "");
}

function parseGradients(svg) {
  const gradients = {};
  const re = /<linearGradient id="([^"]+)"[^>]*>([\s\S]*?)<\/linearGradient>/g;
  let m;
  while ((m = re.exec(svg))) {
    const stops = [];
    const stopRe = /<stop[^/]*\/>/g;
    let sm;
    while ((sm = stopRe.exec(m[2]))) {
      const a = parseAttrs(sm[0]);
      stops.push({ color: a["stop-color"] ?? null, opacity: a["stop-opacity"] ?? "1" });
    }
    gradients[m[1]] = stops;
  }
  return gradients;
}

function resolveFill(fill, gradients) {
  const m = /^url\(#(.+)\)$/.exec(fill ?? "");
  if (!m) return fill ?? null;
  const stops = gradients[m[1]];
  if (!stops) return fill;
  return `gradient(${stops.map((s) => s.color).join(" -> ")})`;
}

// bbox superset (les points de contrôle des courbes C sont inclus tels
// quels : la courbe reste dans leur enveloppe convexe, donc c'est sûr).
function pathBBox(d) {
  let x = 0;
  let y = 0;
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  const extend = (px, py) => {
    if (px < minX) minX = px;
    if (px > maxX) maxX = px;
    if (py < minY) minY = py;
    if (py > maxY) maxY = py;
  };
  const cmdRe = /([MLHVCZ])([^MLHVCZ]*)/g;
  let cm;
  while ((cm = cmdRe.exec(d))) {
    const cmd = cm[1];
    const nums = (cm[2].match(/-?\d*\.?\d+(?:e-?\d+)?/g) ?? []).map(Number);
    if (cmd === "M" || cmd === "L") {
      for (let i = 0; i + 1 < nums.length; i += 2) {
        x = nums[i];
        y = nums[i + 1];
        extend(x, y);
      }
    } else if (cmd === "H") {
      for (const n of nums) {
        x = n;
        extend(x, y);
      }
    } else if (cmd === "V") {
      for (const n of nums) {
        y = n;
        extend(x, y);
      }
    } else if (cmd === "C") {
      for (let i = 0; i + 5 < nums.length; i += 6) {
        extend(nums[i], nums[i + 1]);
        extend(nums[i + 2], nums[i + 3]);
        x = nums[i + 4];
        y = nums[i + 5];
        extend(x, y);
      }
    }
    // Z: pas de coordonnées.
  }
  if (!Number.isFinite(minX)) return null;
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

function decodeEntities(s) {
  return s
    .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(parseInt(dec, 10)))
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'");
}

function parseFontWeight(w) {
  if (w === undefined) return 400;
  if (w === "bold") return 700;
  if (w === "normal") return 400;
  return Number(w);
}

function parseLetterSpacing(ls) {
  if (ls === undefined) return 0;
  return Number(ls.replace("em", ""));
}

function extract(svgPath) {
  let svg = readFileSync(svgPath, "utf8");
  const gradients = parseGradients(svg);
  svg = stripBlocks(svg, "defs");
  svg = stripBlocks(svg, "clipPath");
  svg = stripBlocks(svg, "mask");

  const rects = [];
  const pathBoxes = [];
  const texts = [];
  const stack = [{ x: 0, y: 0 }];

  const tagRe = /<(\/?)(\w+)((?:\s+[\w:-]+\s*=\s*"[^"]*")*)\s*(\/?)>/g;
  let m;
  while ((m = tagRe.exec(svg))) {
    const [, closing, tagName, attrStr, selfClose] = m;
    if (closing === "/") {
      if (tagName === "g") stack.pop();
      continue;
    }
    const attrs = parseAttrs(attrStr);
    const top = stack[stack.length - 1];

    if (tagName === "text") {
      const closeIdx = svg.indexOf("</text>", tagRe.lastIndex);
      const inner = svg.slice(tagRe.lastIndex, closeIdx);
      const tspanRe = /<tspan([^>]*)>([\s\S]*?)<\/tspan>/g;
      const lines = [];
      let tm;
      while ((tm = tspanRe.exec(inner))) {
        const tspanAttrs = parseAttrs(tm[1]);
        lines.push({
          text: decodeEntities(tm[2]),
          x: round2(Number(tspanAttrs.x ?? 0) + top.x),
          baselineY: round2(Number(tspanAttrs.y ?? 0) + top.y),
        });
      }
      if (lines.length > 0) {
        texts.push({
          lines,
          lineHeight: lines.length > 1 ? round2(lines[1].baselineY - lines[0].baselineY) : null,
          fontFamily: attrs["font-family"] ?? null,
          fontSize: attrs["font-size"] !== undefined ? Number(attrs["font-size"]) : null,
          fontWeight: parseFontWeight(attrs["font-weight"]),
          letterSpacingEm: parseLetterSpacing(attrs["letter-spacing"]),
          fill: resolveFill(attrs.fill, gradients),
          fillOpacity: attrs["fill-opacity"] ?? null,
        });
      }
      tagRe.lastIndex = closeIdx + "</text>".length;
      continue;
    }

    if (tagName === "g") {
      let dx = 0;
      let dy = 0;
      const tm = /translate\(\s*(-?\d*\.?\d+)[,\s]+(-?\d*\.?\d+)\s*\)/.exec(attrs.transform ?? "");
      if (tm) {
        dx = Number(tm[1]);
        dy = Number(tm[2]);
      }
      const next = { x: top.x + dx, y: top.y + dy };
      if (!selfClose) stack.push(next);
      continue;
    }

    if (tagName === "rect") {
      rects.push({
        x: round2(Number(attrs.x ?? 0) + top.x),
        y: round2(Number(attrs.y ?? 0) + top.y),
        width: round2(Number(attrs.width ?? 0)),
        height: round2(Number(attrs.height ?? 0)),
        rx: attrs.rx !== undefined ? round2(Number(attrs.rx)) : null,
        fill: resolveFill(attrs.fill, gradients),
        fillOpacity: attrs["fill-opacity"] ?? null,
        stroke: attrs.stroke ?? null,
        strokeOpacity: attrs["stroke-opacity"] ?? null,
        opacity: attrs.opacity ?? null,
      });
    } else if (tagName === "path") {
      const bbox = pathBBox(attrs.d ?? "");
      if (bbox && bbox.width > 0 && bbox.height > 0) {
        pathBoxes.push({
          x: round2(bbox.x + top.x),
          y: round2(bbox.y + top.y),
          width: round2(bbox.width),
          height: round2(bbox.height),
          fill: resolveFill(attrs.fill, gradients),
          fillOpacity: attrs["fill-opacity"] ?? null,
        });
      }
    }
  }

  // Regroupe les paths proches (glyphes d'un même mot/ligne) par
  // union-find : liés s'ils se chevauchent verticalement et sont proches
  // horizontalement (même ligne de texte) ou proches verticalement et
  // alignés horizontalement (icônes multi-traits).
  const n = pathBoxes.length;
  const parent = Array.from({ length: n }, (_, i) => i);
  const find = (i) => (parent[i] === i ? i : (parent[i] = find(parent[i])));
  const union = (i, j) => {
    const ri = find(i);
    const rj = find(j);
    if (ri !== rj) parent[ri] = rj;
  };
  const overlaps1D = (a0, a1, b0, b1, gap) => a0 <= b1 + gap && b0 <= a1 + gap;
  for (let i = 0; i < n; i++) {
    for (let j = i + 1; j < n; j++) {
      const a = pathBoxes[i];
      const b = pathBoxes[j];
      const sameLine =
        overlaps1D(a.y, a.y + a.height, b.y, b.y + b.height, 1) &&
        overlaps1D(a.x, a.x + a.width, b.x, b.x + b.width, 14);
      if (sameLine) union(i, j);
    }
  }
  const groups = new Map();
  for (let i = 0; i < n; i++) {
    const r = find(i);
    if (!groups.has(r)) groups.set(r, []);
    groups.get(r).push(pathBoxes[i]);
  }
  const icons = [...groups.values()].map((boxes) => {
    const minX = Math.min(...boxes.map((b) => b.x));
    const minY = Math.min(...boxes.map((b) => b.y));
    const maxX = Math.max(...boxes.map((b) => b.x + b.width));
    const maxY = Math.max(...boxes.map((b) => b.y + b.height));
    return {
      x: round2(minX),
      y: round2(minY),
      width: round2(maxX - minX),
      height: round2(maxY - minY),
      strokeCount: boxes.length,
      fill: boxes[0].fill,
      fillOpacity: boxes[0].fillOpacity,
    };
  });
  icons.sort((a, b) => a.y - b.y || a.x - b.x);
  rects.sort((a, b) => a.y - b.y || a.x - b.x);
  texts.sort((a, b) => a.lines[0].baselineY - b.lines[0].baselineY || a.lines[0].x - b.lines[0].x);

  return { rects, texts, icons };
}

const file = process.argv[2];
if (!file) {
  console.error("Usage: node extract-specs.mjs <fichier.svg>");
  process.exit(1);
}
console.log(JSON.stringify(extract(file), null, 2));
