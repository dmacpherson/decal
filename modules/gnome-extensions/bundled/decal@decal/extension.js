// Decal Tweaks: GNOME Shell tweaks no other extension does (decal installs and configures it).
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import St from 'gi://St';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import {accentCss, readableFg, validColor} from './accent.js';

export default class DecalTweaks extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._context = St.ThemeContext.get_for_stage(global.stage);
        this._n = 0;
        // re-apply when the settings change, and when GNOME swaps its theme (dark/light/high contrast)
        this._settingsId = this._settings.connect('changed', () => this._applyAccent());
        // (loading our own stylesheet also emits 'changed': only a different theme object means GNOME swapped it)
        this._contextId = this._context.connect('changed', () => {
            if (this._context.get_theme() !== this._theme)
                this._applyAccent();
        });
        this._applyAccent();
    }

    disable() {
        this._settings.disconnect(this._settingsId);
        this._context.disconnect(this._contextId);
        this._unloadAccent();
        this._settings = null;
        this._context = null;
    }

    _applyAccent() {
        if (this._busy)
            return;
        this._busy = true;
        try {
            this._doApplyAccent();
        } finally {
            this._busy = false;
        }
    }

    _doApplyAccent() {
        this._unloadAccent();
        if (!this._settings.get_boolean('accent-enabled'))
            return;
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

    _unloadAccent() {
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
