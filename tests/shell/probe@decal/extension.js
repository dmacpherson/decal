// Test probe for tests/shell/run.sh: checks Decal Tweaks from inside a headless GNOME Shell.
// Writes $PROBE_OUT.txt (JSON), $PROBE_OUT.png (Quick Settings open) and $PROBE_OUT.done.
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Shell from 'gi://Shell';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const after = (ms, fn) => GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => { fn(); return GLib.SOURCE_REMOVE; });

export default class Probe extends Extension {
    enable() {
        const out = GLib.getenv('PROBE_OUT');
        const result = {};
        const finish = () => {
            GLib.file_set_contents(`${out}.txt`, JSON.stringify(result));
            GLib.file_set_contents(`${out}.done`, '');
        };
        after(8000, () => {
            Main.overview.hide();
            after(2000, () => {
                // accent: which custom stylesheets are loaded, and a screenshot with Quick Settings open
                const ext = Main.extensionManager.lookup('decal@decal');
                result.state = ext?.state;
                result.error = String(ext?.error ?? '');
                result.sheets = St.ThemeContext.get_for_stage(global.stage).get_theme()
                    .get_custom_stylesheets().map(f => f.get_path());
                Main.panel.statusArea.quickSettings.menu.open(false);
                after(1500, () => {
                    const stream = Gio.File.new_for_path(`${out}.png`).replace(null, false, Gio.FileCreateFlags.NONE, null);
                    new Shell.Screenshot().screenshot(false, stream, (o, res) => {
                        try { o.screenshot_finish(res); } catch (e) { result.shotError = String(e); }
                        stream.close(null);
                        Main.panel.statusArea.quickSettings.menu.close(false);
                        this._minimizeCheck(result, finish);
                    });
                });
            });
        });
    }

    // instant minimize: minimise the test window and look whether GNOME is animating it shortly after
    _minimizeCheck(result, finish) {
        const actor = global.get_window_actors().find(a => a.meta_window.get_title() === 'decal-test-window');
        if (!actor) {
            result.minimize = 'no test window';
            finish();
            return;
        }
        after(500, () => {
            actor.meta_window.minimize();
            after(60, () => {
                result.minimizeAnimating = Main.wm._minimizing.has(actor);
                result.minimized = actor.meta_window.minimized;
                finish();
            });
        });
    }

    disable() {}
}
