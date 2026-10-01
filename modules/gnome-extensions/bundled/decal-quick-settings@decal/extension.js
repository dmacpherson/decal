// decal Quick Settings: hide the Quick Settings tiles listed in the "hide" setting.
// GNOME lays out only visible tiles, so a hidden tile leaves no gap.
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// profile names -> GNOME's tile classes (js/ui/status/*.js)
const TILES = {
    'dark-style': 'DarkModeToggle',
    'night-light': 'NightLightToggle',
    'do-not-disturb': 'DoNotDisturbToggle',
    'power-mode': 'PowerProfilesToggle',
    'background-apps': 'BackgroundAppsToggle',
    'wired': 'NMWiredToggle',
    'wifi': 'NMWirelessToggle',
    'bluetooth': 'NMBluetoothToggle',
    'vpn': 'NMVpnToggle',
};

export default class DecalQuickSettings extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._hidden = new Map();   // tile -> [its visibility before, notify::visible handler]
        this._grid = Main.panel.statusArea.quickSettings.menu._grid;
        // tiles are added as their indicators load, some after the extension starts
        this._addedId = this._grid.connect('child-added', () => this._apply());
        this._changedId = this._settings.connect('changed::hide', () => this._apply());
        this._apply();
    }

    disable() {
        this._grid.disconnect(this._addedId);
        this._settings.disconnect(this._changedId);
        this._restore();
        this._settings = null;
        this._grid = null;
    }

    _apply() {
        const wanted = new Set(this._settings.get_strv('hide').map(n => TILES[n] ?? n));
        this._restore();
        for (const tile of this._grid.get_children()) {
            if (!wanted.has(tile.constructor.name))
                continue;
            // GNOME may show a tile again (e.g. when its feature changes state): keep it hidden
            const id = tile.connect('notify::visible', () => {
                if (tile.visible)
                    tile.hide();
            });
            this._hidden.set(tile, [tile.visible, id]);
            tile.hide();
        }
    }

    _restore() {
        for (const [tile, [wasVisible, id]] of this._hidden) {
            tile.disconnect(id);
            tile.visible = wasVisible;
        }
        this._hidden.clear();
    }
}
