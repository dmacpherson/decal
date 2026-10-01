// Test probe for tests/shell/run.sh: checks Decal Tweaks from inside a headless GNOME Shell.
// Writes $PROBE_OUT.txt (JSON), $PROBE_OUT.png (Quick Settings open) and $PROBE_OUT.done.
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import Shell from 'gi://Shell';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const after = (ms, fn) => GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => { fn(); return GLib.SOURCE_REMOVE; });
const gtkCss = () => {
    try {
        return new TextDecoder().decode(GLib.file_get_contents(`${GLib.get_user_config_dir()}/gtk-4.0/gtk.css`)[1]);
    } catch {
        return '';
    }
};
let started = false; // the lock check switches extensions off and on again: run once

export default class Probe extends Extension {
    enable() {
        if (started)
            return;
        started = true;
        const out = GLib.getenv('PROBE_OUT');
        const result = {};
        const write = () => {
            GLib.file_set_contents(`${out}.txt`, JSON.stringify(result));
            GLib.file_set_contents(`${out}.done`, '');
        };
        const finish = () => this._lockCheck(result, () => this._offCheck(result, write));
        after(8000, () => {
            Main.overview.hide();
            after(2000, () => {
                // accent: which custom stylesheets are loaded and the colours they give
                const ext = Main.extensionManager.lookup('decal@decal');
                result.state = ext?.state;
                result.error = String(ext?.error ?? '');
                const theme = St.ThemeContext.get_for_stage(global.stage).get_theme();
                result.sheets = [theme.default_stylesheet, ...theme.get_custom_stylesheets()].map(f => f.get_uri());
                // another extension's stylesheet arriving while Decal Tweaks runs
                theme.load_stylesheet(this.dir.get_child('late.css'));
                after(500, () => {
                    result.colors = this._colors();
                    this._screenshot(result, finish);
                });
            });
        });
    }

    // computed colours of widgets styled by GNOME, the accent-user@decal fixture and late.css
    _colors() {
        const hex = c => `#${[c.red, c.green, c.blue].map(v => v.toString(16).padStart(2, '0')).join('')}`;
        const calendar = new St.BoxLayout({style_class: 'calendar'});
        // unclickable, so :insensitive: GNOME's rule for that is more specific than the fixture's, yet loses to it
        const today = new St.Label({style_class: 'calendar-day calendar-today', text: '1'});
        calendar.add_child(today);
        const icon = new St.Label({style_class: 'decal-test-icon', text: 'x'});
        const dot = new St.Widget({style_class: 'decal-test-dot'});
        const late = new St.Label({style_class: 'decal-test-late', text: 'x'});
        const toggle = new St.Button({style_class: 'quick-toggle', toggle_mode: true, checked: true});
        const actors = [calendar, icon, dot, late, toggle];
        actors.forEach(a => Main.uiGroup.add_child(a));
        const colors = {
            icon: hex(icon.get_theme_node().get_foreground_color()),
            dot: hex(dot.get_theme_node().get_background_color()),
            late: hex(late.get_theme_node().get_foreground_color()),
            today: hex(today.get_theme_node().get_background_color()),
            toggle: hex(toggle.get_theme_node().get_background_color()),
        };
        actors.forEach(a => a.destroy());
        return colors;
    }

    // a screenshot with Quick Settings open
    _screenshot(result, finish) {
        Main.panel.statusArea.quickSettings.menu.open(false);
        after(1500, () => {
            const stream = Gio.File.new_for_path(`${GLib.getenv('PROBE_OUT')}.png`)
                .replace(null, false, Gio.FileCreateFlags.NONE, null);
            new Shell.Screenshot().screenshot(false, stream, (o, res) => {
                try { o.screenshot_finish(res); } catch (e) { result.shotError = String(e); }
                stream.close(null);
                Main.panel.statusArea.quickSettings.menu.close(false);
                this._minimizeCheck(result, finish);
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

    // on the lock screen the accent stays (Decal Tweaks runs there too), and so does the apps' colour
    _lockCheck(result, finish) {
        Main.sessionMode.pushMode('unlock-dialog');
        after(500, () => {
            result.lockedToggle = this._colors().toggle;
            result.lockedGtk = gtkCss().includes('--accent-bg-color');
            Main.sessionMode.popMode('unlock-dialog');
            after(1000, () => {
                result.unlockedState = Main.extensionManager.lookup('decal@decal')?.state;
                finish();
            });
        });
    }

    // accent switched off while running: GNOME's theme and accent come back, the other stylesheets stay
    _offCheck(result, finish) {
        Main.extensionManager.lookup('decal@decal')?.stateObj?.getSettings().set_boolean('accent-enabled', false);
        after(500, () => {
            const theme = St.ThemeContext.get_for_stage(global.stage).get_theme();
            const sheets = [theme.default_stylesheet, ...theme.get_custom_stylesheets()].map(f => f.get_uri());
            const colors = this._colors();
            result.offToggle = colors.toggle;
            result.offIcon = colors.icon;
            result.offOurs = sheets.filter(u => u.includes('decal-accent')).length;
            result.offOthers = sheets.filter(u => /accent-user@decal|late\.css/.test(u)).length;
            result.offGtk = gtkCss().includes('--accent-bg-color');
            finish();
        });
    }

    disable() {}
}
