import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Shell from 'gi://Shell';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
export default class Probe extends Extension {
    enable() {
        const out = GLib.getenv('PROBE_OUT');
        GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 8, () => {
            Main.overview.hide();
            GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
                Main.panel.statusArea.quickSettings.menu.open(false);
                GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
                    const sheets = St.ThemeContext.get_for_stage(global.stage).get_theme()
                        .get_custom_stylesheets().map(f => f.get_path());
                    const ext = Main.extensionManager.lookup('decal@decal');
                    const theme = St.ThemeContext.get_for_stage(global.stage).get_theme();
                    let app = null; try { app = theme.application_stylesheet?.get_uri(); } catch (e) { app = 'ERR ' + e; }
                    GLib.file_set_contents(out + '.txt', JSON.stringify({sheets, state: ext?.state, error: String(ext?.error ?? ''),
                        app, files: [...(Gio.File.new_for_path(GLib.get_user_runtime_dir()).enumerate_children('standard::name', 0, null))].map(i => i.get_name()).filter(n => n.startsWith('decal'))}));
                    const file = Gio.File.new_for_path(out + '.png');
                    const stream = file.replace(null, false, Gio.FileCreateFlags.NONE, null);
                    new Shell.Screenshot().screenshot(false, stream, (o, res) => {
                        try { o.screenshot_finish(res); } catch (e) { GLib.file_set_contents(out + '.err', String(e)); }
                        stream.close(null);
                        GLib.file_set_contents(out + '.done', '');
                    });
                    return GLib.SOURCE_REMOVE;
                });
                return GLib.SOURCE_REMOVE;
            });
            return GLib.SOURCE_REMOVE;
        });
    }
    disable() {}
}
