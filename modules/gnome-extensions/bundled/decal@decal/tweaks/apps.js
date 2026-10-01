// Apps too (setting accent-apps, with accent-enabled): the accent colour also for GTK apps, as a marked block in
// GTK's user stylesheets: ~/.config/gtk-4.0/gtk.css (libadwaita) and gtk-3.0/gtk.css (adw-gtk3). Apps read them
// when they start. Only switching it or the extension off takes the block out: if GNOME switches the extension
// off for a screen lock (it normally runs there too, see metadata.json), the apps keep running and keep their colour.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {gtkAccentCss, readableFg, validColor, withBlock} from './accent-css.js';

const KEYS = ['accent-enabled', 'accent-apps', 'accent-color', 'accent-fg-color'];

// write file with block in it (or out of it, block ''), leaving the rest of the file alone
function update(file, block) {
    let text = '';
    try {
        text = new TextDecoder().decode(file.load_contents(null)[1]);
    } catch (e) {
        if (!e.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.NOT_FOUND))
            throw e;
    }
    const next = withBlock(text, block);
    if (next === text)
        return;
    if (!next) {
        file.delete(null);
        return;
    }
    GLib.mkdir_with_parents(file.get_parent().get_path(), 0o755);
    // replace_contents follows a symlinked gtk.css (dotfiles) instead of replacing the link
    file.replace_contents(new TextEncoder().encode(next), null, false, Gio.FileCreateFlags.NONE, null);
}

export class AppsAccent {
    constructor(settings) {
        this._settings = settings;
    }

    start() {
        this._ids = KEYS.map(k => this._settings.connect(`changed::${k}`, () => this._sync()));
        this._sync();
    }

    stop() {
        this._ids.forEach(id => this._settings.disconnect(id));
        if (!Main.sessionMode.isLocked)
            this._write('');
    }

    _sync() {
        const color = this._settings.get_string('accent-color');
        let fg = this._settings.get_string('accent-fg-color');
        if (!validColor(fg))
            fg = validColor(color) ? readableFg(color) : '';
        const on = this._settings.get_boolean('accent-enabled') && this._settings.get_boolean('accent-apps') &&
            validColor(color);
        this._write(on ? {color, fg} : '');
    }

    _write(accent) {
        for (const gtk of [4, 3]) {
            const file = Gio.File.new_for_path(GLib.build_filenamev([GLib.get_user_config_dir(), `gtk-${gtk}.0`, 'gtk.css']));
            try {
                update(file, accent && gtkAccentCss(gtk, accent.color, accent.fg));
            } catch (e) {
                console.warn(`Decal Tweaks: can't update ${file.get_path()}: ${e.message}`);
            }
        }
    }
}
