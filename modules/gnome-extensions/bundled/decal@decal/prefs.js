// Decal Tweaks settings window (Extensions app → Decal Tweaks → Settings)
import Adw from 'gi://Adw';
import Gdk from 'gi://Gdk';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';
import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

export default class DecalTweaksPrefs extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();
        const page = new Adw.PreferencesPage();
        const group = new Adw.PreferencesGroup({
            title: 'Accent colour',
            description: 'Any colour for GNOME Shell: top bar, Quick Settings, sliders, switches. Apps keep GNOME\'s accent.',
        });
        const on = new Adw.SwitchRow({title: 'Custom accent colour'});
        settings.bind('accent-enabled', on, 'active', Gio.SettingsBindFlags.DEFAULT);
        group.add(on);

        const rgba = new Gdk.RGBA();
        rgba.parse(settings.get_string('accent-color'));
        const button = new Gtk.ColorDialogButton({
            dialog: new Gtk.ColorDialog({with_alpha: false}), rgba, valign: Gtk.Align.CENTER,
        });
        button.connect('notify::rgba', () => {
            const c = button.rgba;
            const hex = '#' + [c.red, c.green, c.blue].map(v => Math.round(v * 255).toString(16).padStart(2, '0')).join('');
            settings.set_string('accent-color', hex);
        });
        const row = new Adw.ActionRow({title: 'Colour'});
        row.add_suffix(button);
        settings.bind('accent-enabled', row, 'sensitive', Gio.SettingsBindFlags.GET);
        group.add(row);

        page.add(group);

        const windows = new Adw.PreferencesGroup({title: 'Windows'});
        const instant = new Adw.SwitchRow({title: 'Instant minimize', subtitle: 'No minimize animation; other animations stay'});
        settings.bind('instant-minimize', instant, 'active', Gio.SettingsBindFlags.DEFAULT);
        windows.add(instant);
        page.add(windows);
        window.add(page);
    }
}
