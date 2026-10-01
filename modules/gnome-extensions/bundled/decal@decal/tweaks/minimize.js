// Tweak: minimize windows instantly; every other animation stays as it is.
// When a window becomes minimized we ask GNOME to skip its next effect (Main.wm.skipNextEffect, the
// Shell's own mechanism), which is the minimize animation that follows.
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

export class InstantMinimizeTweak {
    enable() {
        this._windows = new Map();   // Meta.Window -> [notify::minimized id, unmanaged id]
        global.get_window_actors().forEach(a => this._track(a.meta_window));
        this._createdId = global.display.connect('window-created', (_d, w) => this._track(w));
    }

    disable() {
        global.display.disconnect(this._createdId);
        for (const [w, ids] of this._windows)
            ids.forEach(id => w.disconnect(id));
        this._windows.clear();
    }

    _track(win) {
        if (this._windows.has(win))
            return;
        const minimizedId = win.connect('notify::minimized', () => {
            const actor = win.get_compositor_private();
            if (win.minimized && actor?.visible)
                Main.wm.skipNextEffect(actor);
        });
        const unmanagedId = win.connect('unmanaged', () => {
            win.disconnect(minimizedId);
            win.disconnect(unmanagedId);
            this._windows.delete(win);
        });
        this._windows.set(win, [minimizedId, unmanagedId]);
    }
}
