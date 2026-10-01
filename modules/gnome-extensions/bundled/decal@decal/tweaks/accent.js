// Tweak: any accent colour for GNOME Shell (settings: accent-color, accent-fg-color).
// The overrides are rebuilt from the running Shell's own stylesheet (see accent-css.js).
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';
import {accentCss, readableFg, validColor} from './accent-css.js';

export class AccentTweak {
    constructor(settings) {
        this._settings = settings;
        this._n = 0;
    }

    enable() {
        this._context = St.ThemeContext.get_for_stage(global.stage);
        this._settingsIds = ['changed::accent-color', 'changed::accent-fg-color']
            .map(s => this._settings.connect(s, () => this._apply()));
        // loading our own stylesheet also emits 'changed': only a different theme object means GNOME
        // swapped it (dark/light/high contrast)
        this._contextId = this._context.connect('changed', () => {
            if (this._context.get_theme() !== this._theme)
                this._apply();
        });
        this._apply();
    }

    disable() {
        this._settingsIds.forEach(id => this._settings.disconnect(id));
        this._context.disconnect(this._contextId);
        this._unload();
        this._context = null;
    }

    _apply() {
        if (this._busy)
            return;
        this._busy = true;
        try {
            this._unload();
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
        const theme = this._context.get_theme();
        if (!theme)
            return;
        // GNOME's own stylesheet is the theme's default_stylesheet; a custom Shell theme (User Themes) is
        // its application_stylesheet: override the accent in both, the custom theme's rules last
        const sources = [theme.default_stylesheet, theme.application_stylesheet].filter(f => f);
        const css = sources.map(f => accentCss(new TextDecoder().decode(f.load_contents(null)[1]), color, fg)).join('\n');
        // a fresh file each time: St caches stylesheets by file
        const path = GLib.build_filenamev([GLib.get_user_runtime_dir(), `decal-accent-${this._n++}.css`]);
        GLib.file_set_contents(path, css);
        this._file = Gio.File.new_for_path(path);
        this._theme = theme;
        theme.load_stylesheet(this._file);
    }

    _unload() {
        if (!this._file)
            return;
        // GNOME copies extension stylesheets into a new theme (dark/light switch): unload from both
        this._theme?.unload_stylesheet(this._file);
        this._context?.get_theme()?.unload_stylesheet(this._file);
        try {
            this._file.delete(null);
        } catch {}
        this._file = null;
        this._theme = null;
    }
}
