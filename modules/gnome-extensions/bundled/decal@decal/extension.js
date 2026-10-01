// Decal Tweaks: GNOME Shell tweaks no other extension does (decal installs and configures it).
// Each tweak lives in tweaks/ and is switched on and off by its own setting.
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import {AccentTweak} from './tweaks/accent.js';
import {AppsAccent} from './tweaks/apps.js';
import {InstantMinimizeTweak} from './tweaks/minimize.js';

const TWEAKS = [
    {key: 'accent-enabled', make: settings => new AccentTweak(settings)},
    {key: 'instant-minimize', make: () => new InstantMinimizeTweak()},
];

export default class DecalTweaks extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._running = new Map();   // key -> tweak
        this._ids = TWEAKS.map(t => this._settings.connect(`changed::${t.key}`, () => this._sync(t)));
        TWEAKS.forEach(t => this._sync(t));
        this._apps = new AppsAccent(this._settings);
        this._apps.start();
    }

    disable() {
        this._apps.stop();
        this._apps = null;
        this._ids.forEach(id => this._settings.disconnect(id));
        for (const tweak of this._running.values())
            tweak.disable();
        this._running.clear();
        this._settings = null;
    }

    _sync(t) {
        const want = this._settings.get_boolean(t.key);
        const tweak = this._running.get(t.key);
        if (want && !tweak) {
            const created = t.make(this._settings);
            try {
                created.enable();
                this._running.set(t.key, created);
            } catch (e) {
                console.error(`Decal Tweaks: ${t.key} failed: ${e}`);
            }
        } else if (!want && tweak) {
            tweak.disable();
            this._running.delete(t.key);
        }
    }
}
