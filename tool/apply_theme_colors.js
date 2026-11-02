const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', 'lib');
const skip = new Set([
  path.normalize(path.join(root, 'screens', 'splash_screen.dart')),
  path.normalize(path.join(root, 'theme', 'app_theme.dart')),
  path.normalize(path.join(root, 'widgets', 'vite_loader.dart')),
]);

function walk(dir, out = []) {
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    const stat = fs.statSync(full);
    if (stat.isDirectory()) walk(full, out);
    else if (name.endsWith('.dart')) out.push(full);
  }
  return out;
}

function rgb(hex) {
  const n = parseInt(hex, 16);
  return { a: (n >>> 24) & 255, r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}

function isNearWhite(hex) {
  const { a, r, g, b } = rgb(hex);
  return a >= 240 && r >= 232 && g >= 232 && b >= 232;
}

function textRole(hex) {
  const { a, r, g, b } = rgb(hex);
  if (a < 240) return null;
  if (g > r + 30 && g > b + 10 && g > 80) return null;
  if (r > 140 && g < 90 && b < 90) return null;
  if (b > r + 40 && b > 120 && r < 80) return null;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  if (max < 90) return 'onSurface';
  if (max < 175 && min > 40 && max - min < 80) return 'onSurfaceVariant';
  return null;
}

function fillReplacement(before, prop) {
  const window = before.slice(-500);
  const textish = /TextStyle\s*\(|Icon\s*\(|foregroundColor\s*:|style\s*:\s*(?:const\s+)?TextStyle/.test(window.slice(-140));
  if (textish && prop === 'color') return null;
  const scaffold = /Scaffold\s*\(/.test(window) && !/BoxDecoration\s*\(/.test(window.slice(window.lastIndexOf('Scaffold')));
  if (prop === 'backgroundColor' && /Scaffold\s*\(/.test(window.slice(-180))) {
    return 'backgroundColor: Theme.of(context).scaffoldBackgroundColor';
  }
  const fill = /BoxDecoration\s*\(|Scaffold\s*\(|Material\s*\(|Card\s*\(|ColoredBox\s*\(|Container\s*\(|DecoratedBox\s*\(|decoration\s*:|color\s*:/.test(window);
  if (!fill && prop !== 'backgroundColor') return null;
  if (scaffold) return `${prop}: Theme.of(context).scaffoldBackgroundColor`;
  return `${prop}: Theme.of(context).colorScheme.surface`;
}

function replaceFills(src) {
  src = src.replace(/(?<![A-Za-z])(backgroundColor|color)\s*:\s*(?:const\s+)?Colors\.white\b/g, (full, prop, offset, whole) => {
    const before = whole.slice(Math.max(0, offset - 500), offset);
    if (prop === 'color') {
      const window = before.slice(-160);
      if (/TextStyle\s*\(|Icon\s*\(|foregroundColor\s*:|style\s*:/.test(window)) return full;
      if (!/BoxDecoration\s*\(|Container\s*\(|Material\s*\(|Card\s*\(|ColoredBox\s*\(|DecoratedBox\s*\(|decoration\s*:/.test(before.slice(-400))) {
        return full;
      }
    }
    const next = fillReplacement(before, prop);
    return next || full;
  });

  src = src.replace(/(?<![A-Za-z])(backgroundColor|color)\s*:\s*(?:const\s+)?Color\(\s*0x([A-Fa-f0-9]{8})\s*\)/g, (full, prop, hex, offset, whole) => {
    if (!isNearWhite(hex)) return full;
    const before = whole.slice(Math.max(0, offset - 500), offset);
    const next = fillReplacement(before, prop);
    return next || full;
  });
  return src;
}

function replaceText(src) {
  src = src.replace(/(?<![A-Za-z])color\s*:\s*(?:const\s+)?Colors\.black87\b/g, (full, offset, whole) => {
    const before = whole.slice(Math.max(0, offset - 120), offset);
    if (/BoxShadow\s*\(/.test(before)) return full;
    return 'color: Theme.of(context).colorScheme.onSurface';
  });
  src = src.replace(/(?<![A-Za-z])color\s*:\s*(?:const\s+)?Colors\.black\b/g, (full, offset, whole) => {
    const before = whole.slice(Math.max(0, offset - 140), offset);
    if (/BoxShadow\s*\(/.test(before)) return full;
    if (/backgroundColor\s*:\s*$/.test(before)) return full;
    return 'color: Theme.of(context).colorScheme.onSurface';
  });
  src = src.replace(/(?<![A-Za-z])color\s*:\s*(?:const\s+)?Color\(\s*0x([A-Fa-f0-9]{8})\s*\)/g, (full, hex, offset, whole) => {
    const role = textRole(hex);
    if (!role) return full;
    const before = whole.slice(Math.max(0, offset - 180), offset);
    if (/BoxShadow\s*\(|BoxDecoration\s*\(|backgroundColor\s*:/.test(before.slice(-80))) return full;
    if (!/TextStyle\s*\(|Text\s*\(|Icon\s*\(|style\s*:/.test(before)) return full;
    const token = role === 'onSurfaceVariant' ? 'onSurfaceVariant' : 'onSurface';
    return `color: Theme.of(context).colorScheme.${token}`;
  });
  return src;
}

function stripConst(src) {
  let guard = 0;
  let current = src;
  while (current.includes('Theme.of(context)') && guard++ < 8) {
    const ranges = [];
    const constRe = /\bconst\b/g;
    let m;
    while ((m = constRe.exec(current))) {
      let i = m.index + 5;
      while (i < current.length && /\s/.test(current[i])) i++;
      const identStart = i;
      while (i < current.length && /[A-Za-z0-9_<>?.]/.test(current[i])) i++;
      if (i === identStart) continue;
      while (i < current.length && /\s/.test(current[i])) i++;
      if (current[i] !== '(') continue;
      let depth = 0;
      let j = i;
      for (; j < current.length; j++) {
        const ch = current[j];
        if (ch === '(') depth++;
        else if (ch === ')') {
          depth--;
          if (depth === 0) {
            j++;
            break;
          }
        }
      }
      if (current.slice(i, j).includes('Theme.of(context)')) {
        ranges.push([m.index, m.index + 5]);
      }
    }
    if (!ranges.length) break;
    for (let k = ranges.length - 1; k >= 0; k--) {
      let end = ranges[k][1];
      if (current[end] === ' ') end++;
      current = current.slice(0, ranges[k][0]) + current.slice(end);
    }
  }
  return current;
}

function addImport(src) {
  if (!src.includes('ViteLoader(') && !src.includes('ViteLoader ')) return src;
  if (src.includes('widgets/vite_loader.dart')) return src;
  const line = "import 'package:vite_captain/widgets/vite_loader.dart';\n";
  const match = src.match(/^import .+;\r?\n/m);
  if (!match) return line + src;
  const at = match.index + match[0].length;
  return src.slice(0, at) + line + src.slice(at);
}

let files = 0;
for (const file of walk(root)) {
  if (skip.has(path.normalize(file))) continue;
  let src = fs.readFileSync(file, 'utf8');
  const original = src;
  if (src.includes('CircularProgressIndicator')) {
    src = src.replace(/CircularProgressIndicator/g, 'ViteLoader');
    src = addImport(src);
  }
  src = replaceFills(src);
  src = replaceText(src);
  if (src.includes('Theme.of(context)')) src = stripConst(src);
  if (src !== original) {
    fs.writeFileSync(file, src);
    files++;
  }
}
console.log('updated', files);
