// Accent colour stylesheets. GNOME Shell takes its accent only from a fixed list. Stylesheets refer to it as
// -st-accent-color / -st-accent-fg-color (often inside st-mix() etc.). GNOME's own stylesheet is copied whole
// with those replaced (recolor); an extension's stylesheet gets override rules re-declaring exactly its accent
// declarations (accentCss). Built from the running Shell's stylesheets, it follows GNOME updates.
// Pure functions (no Shell imports): unit-tested with gjs.

const ACCENT = /-st-accent-(fg-)?color/;

// css: an extension stylesheet's text; color, fg: '#rrggbb'. Returns override CSS (accent declarations only).
export function accentCss(css, color, fg) {
    const out = [];
    // comments and @-statements (@import url(...);) out: they would glue onto the next selector
    const text = css.replace(/\/\*[\s\S]*?\*\//g, '').replace(/@[^{};]*;/g, '');
    for (const [, selector, body] of text.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
        const sel = selector.trim();
        if (!sel || sel.startsWith('@'))
            continue;
        const decls = body.split(';').map(d => d.trim()).filter(d => ACCENT.test(d));
        if (!decls.length)
            continue;
        const lines = decls.map(d => `  ${recolor(d, color, fg)};`);
        out.push(`${sel} {\n${lines.join('\n')}\n}`);
    }
    return out.join('\n');
}

// css with GNOME's accent replaced by color / fg everywhere
export function recolor(css, color, fg) {
    return css.replaceAll('-st-accent-fg-color', fg).replaceAll('-st-accent-color', color);
}

// css with each url(path) replaced by url("resolve(path)"), so a copy elsewhere still finds the files
export function absoluteUrls(css, resolve) {
    return css.replace(/url\(\s*["']?([^"')]+?)["']?\s*\)/g, (_m, path) => `url("${resolve(path)}")`);
}

// css with each @import replaced by read(path): the imported file's text ('' when it can't be read)
export function inlineImports(css, read) {
    return css.replace(/@import\s+(?:url\(\s*)?["']?([^"')\s;]+)["']?\s*\)?[^;]*;/g, (_m, path) => read(path));
}

// Apps too: GTK's user stylesheets (~/.config/gtk-N.0/gtk.css) get a marked block with the accent.
// decal's gnome-extensions module strips the same markers when it removes the extension.
const BEGIN = '/* decal accent: begin';
const END = '/* decal accent: end';

// the block for GTK 4 (libadwaita derives its other accent shades from these) or GTK 3 (adw-gtk3's colours).
// Plain GTK 4 apps (no libadwaita) have no accent: their built-in theme's colours are fixed.
export function gtkAccentCss(gtk, color, fg) {
    const lines = gtk === 4
        ? [':root {', `  --accent-bg-color: ${color};`, `  --accent-fg-color: ${fg};`, '}']
        : [`@define-color accent_bg_color ${color};`, `@define-color accent_fg_color ${fg};`,
            `@define-color accent_color ${color};`];
    return [`${BEGIN} (Decal Tweaks, "Apps too": edits here are overwritten) */`, ...lines, `${END} */`].join('\n');
}

// a stylesheet's text with our block replaced by block, last so it wins, or removed when block is ''
export function withBlock(text, block) {
    const kept = [];
    let inside = false;
    for (const line of text.split('\n')) {
        if (!inside && line.startsWith(BEGIN))
            inside = true;
        else if (inside && line.startsWith(END))
            inside = false;
        else if (!inside)
            kept.push(line);
    }
    const rest = kept.join('\n').replace(/\s+$/, '');
    if (!block)
        return rest ? `${rest}\n` : '';
    return rest ? `${rest}\n\n${block}\n` : `${block}\n`;
}

// White or black text, whichever is more readable on the colour (WCAG relative luminance).
export function readableFg(hex) {
    const [r, g, b] = [1, 3, 5].map(i => {
        const c = parseInt(hex.slice(i, i + 2), 16) / 255;
        return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
    });
    const lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    return lum > 0.4 ? '#000000' : '#ffffff';
}

export function validColor(s) {
    return /^#[0-9a-fA-F]{6}$/.test(s);
}
