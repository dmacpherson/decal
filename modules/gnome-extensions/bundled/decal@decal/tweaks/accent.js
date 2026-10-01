// Tweak: any accent colour for GNOME Shell (settings: accent-color, accent-fg-color).
// Swaps in a theme like GNOME's own (Main.loadTheme) but recoloured, rebuilt from the running Shell's stylesheets
// (see accent-css.js): GNOME's, and those of extensions that use the accent too (e.g. Just Perfection's
// accent-coloured panel icons).
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {absoluteUrls, accentCss, inlineImports, readableFg, recolor, validColor} from './accent-css.js';

const PREFIX = 'decal-accent-';
let serial = 0; // a fresh file name each time: St caches stylesheets by file

const fileFor = (base, path) => (/^[a-z][a-z0-9+.-]*:/i.test(path)
    ? Gio.File.new_for_uri(path) : base.get_parent().resolve_relative_path(path));

// a stylesheet's text with absolute urls and its @import-ed files inlined, so a copy works from anywhere
function readCss(file, seen = new Set()) {
    if (seen.has(file.get_uri()))
        return '';
    seen.add(file.get_uri());
    const text = absoluteUrls(new TextDecoder().decode(file.load_contents(null)[1]), p => fileFor(file, p).get_uri());
    return inlineImports(text, path => {
        try {
            return readCss(fileFor(file, path), seen);
        } catch {
            return '';
        }
    });
}

export class AccentTweak {
    constructor(settings) {
        this._settings = settings;
        this._files = [];
    }

    enable() {
        this._context = St.ThemeContext.get_for_stage(global.stage);
        this._settingsIds = ['changed::accent-color', 'changed::accent-fg-color']
            .map(s => this._settings.connect(s, () => this._apply()));
        // re-apply when GNOME swapped the theme (dark/light/high contrast, Shell theme) or another extension's
        // stylesheet came or went
        this._contextId = this._context.connect('changed', () => {
            if (this._context.get_theme() !== this._theme || this._othersKey() !== this._seen)
                this._apply();
        });
        this._apply();
    }

    disable() {
        this._settingsIds.forEach(id => this._settings.disconnect(id));
        this._context.disconnect(this._contextId);
        // back to GNOME's theme, keeping the other extensions' stylesheets
        if (this._context.get_theme() === this._theme)
            this._setTheme(this._gnome, Main.getThemeStylesheet(), this._others().map(f => [f]));
        this._delete(this._files);
        this._files = [];
        this._theme = null;
        this._context = null;
    }

    _apply() {
        if (this._busy)
            return;
        this._busy = true;
        try {
            this._load();
        } finally {
            this._busy = false;
        }
    }

    _load() {
        const color = this._settings.get_string('accent-color');
        if (!validColor(color)) {
            console.warn(`Decal Tweaks: accent-color '${color}' is not #rrggbb; GNOME's accent kept`);
            return;
        }
        let fg = this._settings.get_string('accent-fg-color');
        if (!validColor(fg))
            fg = readableFg(color);
        const current = this._context.get_theme();
        if (!current)
            return;
        // GNOME's own stylesheet (its default_stylesheet) and a custom Shell theme (User Themes, Main's theme
        // stylesheet) are copied whole, recoloured: they keep their place below every extension stylesheet.
        if (current !== this._theme)
            this._gnome = current.default_stylesheet;
        const shellTheme = Main.getThemeStylesheet();
        const old = this._files;
        this._files = [];
        const copy = file => file && this._write(recolor(readCss(file), color, fg));
        // St settles a tie between equally specific rules in favour of the custom stylesheet loaded first: an
        // extension's override goes just before that extension's stylesheet
        const sheets = this._others(current).map(sheet => {
            const css = this._override(sheet, color, fg);
            return css ? [this._write(css), sheet] : [sheet];
        });
        this._setTheme(copy(this._gnome), copy(shellTheme), sheets);
        this._delete(old);
    }

    // like Main.loadTheme: a new theme from GNOME's (or our) stylesheets plus the extensions' ones, in order
    _setTheme(defaultSheet, shellTheme, sheets) {
        const theme = new St.Theme({application_stylesheet: shellTheme, default_stylesheet: defaultSheet});
        sheets.flat().forEach(f => theme.load_stylesheet(f));
        this._theme = theme;
        this._context.set_theme(theme);
        this._seen = this._othersKey();
    }

    // the custom stylesheets that aren't ours (other extensions'), in load order
    _others(theme = this._context.get_theme()) {
        return theme?.get_custom_stylesheets().filter(f => !f.get_basename().startsWith(PREFIX)) ?? [];
    }

    _othersKey() {
        return this._others().map(f => f.get_uri()).join('\n');
    }

    // the accent override for an extension's stylesheet ('' when it doesn't use the accent or can't be read)
    _override(file, color, fg) {
        try {
            return accentCss(readCss(file), color, fg);
        } catch (e) {
            console.warn(`Decal Tweaks: can't read ${file.get_uri()}: ${e.message}`);
            return '';
        }
    }

    _write(css) {
        const path = GLib.build_filenamev([GLib.get_user_runtime_dir(), `${PREFIX}${serial++}.css`]);
        GLib.file_set_contents(path, css);
        const file = Gio.File.new_for_path(path);
        this._files.push(file);
        return file;
    }

    _delete(files) {
        for (const file of files) {
            try {
                file.delete(null);
            } catch {}
        }
    }
}
