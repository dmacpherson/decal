// gjs -m tests/shell/gtk-accent.js 3|4 OUT : for tests/shell/run.sh. Opens a GTK 3 or GTK 4 (libadwaita) window with a
// switch on and a suggested-action button, renders it and writes its three most common saturated colours (the
// accent and shades of it) as #rrggbb to OUT.
import GLib from 'gi://GLib';
import GdkPixbuf from 'gi://GdkPixbuf';

const [ver, out] = ARGV;
const Gtk = (await import(`gi://Gtk?version=${ver}.0`)).default;
const png = `${out}.png`;
const loop = new GLib.MainLoop(null, false);
const after = (ms, fn) => GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => { fn(); return GLib.SOURCE_REMOVE; });

function accentsOf(file) {
    const pb = GdkPixbuf.Pixbuf.new_from_file(file);
    const px = pb.get_pixels(), n = pb.get_n_channels(), stride = pb.get_rowstride(), counts = new Map();
    for (let y = 0; y < pb.get_height(); y++) {
        for (let x = 0; x < pb.get_width(); x++) {
            const i = y * stride + x * n, rgb = [px[i], px[i + 1], px[i + 2]];
            if (Math.max(...rgb) - Math.min(...rgb) > 80) {
                const hex = `#${rgb.map(v => v.toString(16).padStart(2, '0')).join('')}`;
                counts.set(hex, (counts.get(hex) ?? 0) + 1);
            }
        }
    }
    return [...counts].sort((a, b) => b[1] - a[1]).slice(0, 3).map(([hex]) => hex).join(' ') || 'none';
}

if (ver === '4')
    (await import('gi://Adw?version=1')).default.init(); // initialises GTK too
else
    Gtk.init(null);
const box = new Gtk.Box({orientation: Gtk.Orientation.VERTICAL, spacing: 12, margin_top: 20, margin_bottom: 20,
    margin_start: 20, margin_end: 20});
const button = new Gtk.Button({label: 'Select'});
button.get_style_context().add_class('suggested-action');
const win = new Gtk.Window({title: 'decal-gtk-accent', default_width: 200, default_height: 140});
if (ver === '4') {
    box.append(new Gtk.Switch({active: true, halign: Gtk.Align.START}));
    box.append(button);
    win.set_child(box);
    win.present();
    after(1500, () => {
        const paintable = new Gtk.WidgetPaintable({widget: box}), snap = new Gtk.Snapshot();
        paintable.snapshot(snap, box.get_width(), box.get_height());
        win.get_renderer().render_texture(snap.to_node(), null).save_to_png(png);
        loop.quit();
    });
} else {
    const cairo = (await import('cairo')).default;
    box.add(new Gtk.Switch({active: true, halign: Gtk.Align.START}));
    box.add(button);
    win.add(box);
    win.show_all();
    after(1500, () => {
        const a = win.get_allocation(), surface = new cairo.ImageSurface(cairo.Format.ARGB32, a.width, a.height);
        const cr = new cairo.Context(surface);
        win.draw(cr);
        surface.writeToPNG(png);
        cr.$dispose();
        loop.quit();
    });
}
loop.run();
GLib.file_set_contents(out, accentsOf(png));
GLib.unlink(png);
