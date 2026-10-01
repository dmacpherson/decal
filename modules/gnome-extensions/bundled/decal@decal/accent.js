// Accent colour: GNOME Shell takes its accent only from a fixed list. Its stylesheet refers to it as
// -st-accent-color / -st-accent-fg-color (often inside st-mix() etc.), so we re-declare exactly those
// rules with a chosen colour. Built from the running Shell's own stylesheet, it follows GNOME updates.
// Pure functions (no Shell imports): unit-tested with gjs.

const ACCENT = /-st-accent-(fg-)?color/;

// css: GNOME Shell stylesheet text; color, fg: '#rrggbb'. Returns override CSS (accent declarations only).
export function accentCss(css, color, fg) {
    const out = [];
    const text = css.replace(/\/\*[\s\S]*?\*\//g, '');
    for (const [, selector, body] of text.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
        const sel = selector.trim();
        if (!sel || sel.startsWith('@'))
            continue;
        const decls = body.split(';').map(d => d.trim()).filter(d => ACCENT.test(d));
        if (!decls.length)
            continue;
        const lines = decls.map(d =>
            `  ${d.replaceAll('-st-accent-fg-color', fg).replaceAll('-st-accent-color', color)};`);
        out.push(`${sel} {\n${lines.join('\n')}\n}`);
    }
    return out.join('\n');
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
