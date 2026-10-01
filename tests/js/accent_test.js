// gjs -m tests/js/accent_test.js [SHELL_CSS] : unit tests for the Decal Tweaks accent stylesheet generator
import GLib from 'gi://GLib';
import {absoluteUrls, accentCss, gtkAccentCss, inlineImports, readableFg, recolor, validColor, withBlock} from '../../modules/gnome-extensions/bundled/decal@decal/tweaks/accent-css.js';

let fails = 0, count = 0;
const eq = (got, want, what) => { count++; if (got !== want) { fails++; print(`  FAIL: ${what}: expected [${want}] got [${got}]`); } };
const has = (s, part, what) => { count++; if (!s.includes(part)) { fails++; print(`  FAIL: ${what}: [${part}] not in [${s}]`); } };
const lacks = (s, part, what) => { count++; if (s.includes(part)) { fails++; print(`  FAIL: ${what}: [${part}] unexpectedly in [${s}]`); } };

const css = `/* comment { not a rule } */
.quick-toggle:checked, .toggle-switch:checked { background-color: -st-accent-color; color: -st-accent-fg-color; border-radius: 99px; }
.slider { -barlevel-active-background-color: st-mix(-st-accent-color, #ffffff, 60%) !important; height: 4px; }
.panel { background-color: black; }
`;
const out = accentCss(css, '#ff40a0', '#ffffff');
has(out, '.quick-toggle:checked, .toggle-switch:checked {', 'selector list kept as is');
has(out, 'background-color: #ff40a0;', 'accent colour replaced');
has(out, 'color: #ffffff;', 'accent text colour replaced');
has(out, 'st-mix(#ff40a0, #ffffff, 60%) !important;', "inside GNOME's own colour functions, !important kept");
lacks(out, 'border-radius', 'non-accent lines dropped (only colours are overridden)');
lacks(out, 'height', 'non-accent lines dropped');
lacks(out, '.panel', 'rules without the accent left out');
lacks(out, 'comment', 'comments ignored');
lacks(out, '-st-accent', 'no accent keyword left');
// extension stylesheets often start with @import: the rule after it must survive
const imp = accentCss('@import url("styles/panel.css");\n.my-icon { color: -st-accent-color; }', '#ff40a0', '#ffffff');
has(imp, '.my-icon {', 'rule after an @import kept');
has(imp, 'color: #ff40a0;', 'rule after an @import overridden');
lacks(imp, '@import', '@import not copied');
const files = {'a.css': '.a { color: red; }', 'dir/b.css': '.b {}'};
const read = path => files[path] ?? '';
eq(inlineImports('@import url("a.css");\n.x {}', read), '.a { color: red; }\n.x {}', '@import url("...") inlined');
eq(inlineImports("@import 'dir/b.css';", read), '.b {}', "@import '...' inlined");
eq(inlineImports('@import url(a.css) screen;', read), '.a { color: red; }', 'unquoted url, media list ignored');
eq(inlineImports('@import url("gone.css");.y {}', read), '.y {}', 'unreadable import dropped');
eq(recolor('.a { color: -st-accent-fg-color; background: st-mix(-st-accent-color, #fff, 5%); height: 4px; }', '#ff40a0', '#000000'),
    '.a { color: #000000; background: st-mix(#ff40a0, #fff, 5%); height: 4px; }', 'recolor: whole stylesheet, everything else kept');
const abs = p => (/^[a-z]+:/.test(p) ? p : `file:///themes/x/${p}`);
eq(absoluteUrls('.a { background-image: url("assets/a.svg"); } .b { background: url(b.png); }', abs),
    '.a { background-image: url("file:///themes/x/assets/a.svg"); } .b { background: url("file:///themes/x/b.png"); }',
    'relative urls made absolute');
eq(absoluteUrls(".c { background-image: url('resource:///org/gnome/shell/theme/c.svg'); }", abs),
    '.c { background-image: url("resource:///org/gnome/shell/theme/c.svg"); }', 'absolute urls kept');
// Apps too: a marked block in GTK's user stylesheets
const g4 = gtkAccentCss(4, '#ff40a0', '#ffffff'), g3 = gtkAccentCss(3, '#ff40a0', '#ffffff');
has(g4, '--accent-bg-color: #ff40a0;', 'GTK 4: libadwaita accent variable');
has(g4, '--accent-fg-color: #ffffff;', 'GTK 4: text on the accent');
has(g3, '@define-color accent_bg_color #ff40a0;', 'GTK 3: adw-gtk3 accent colour');
has(g3, '@define-color accent_fg_color #ffffff;', 'GTK 3: text on the accent');
eq(withBlock('', g4), `${g4}\n`, 'block into an empty file');
eq(withBlock('/* mine */\nwindow { color: red; }\n', g4), `/* mine */\nwindow { color: red; }\n\n${g4}\n`, 'block appended after the user\'s own css');
const once = withBlock('/* mine */\n', g4);
eq(withBlock(once, gtkAccentCss(4, '#00ff00', '#000000')), `/* mine */\n\n${gtkAccentCss(4, '#00ff00', '#000000')}\n`, 'block replaced, not added twice');
eq(withBlock(withBlock('/* mine */\n', g4) + '/* after */\n', ''), '/* mine */\n\n/* after */\n', 'block removed, the rest kept');
eq(withBlock(withBlock('', g4), ''), '', 'nothing left when the file only had our block');
eq(readableFg('#ff40a0'), '#ffffff', 'white text on hot pink');
eq(readableFg('#ffff00'), '#000000', 'black text on yellow');
eq(validColor('#ff40a0'), true, '#rrggbb accepted');
eq(validColor('pink'), false, 'names rejected');
eq(validColor('#ff40a0; } .x { color: red'), false, 'no CSS injection through the colour');

// against GNOME's real stylesheet when one is given
const shell = ARGV[0];
if (shell) {
    const real = new TextDecoder().decode(GLib.file_get_contents(shell)[1]);
    const o = accentCss(real, '#ff40a0', '#ffffff');
    const rules = (o.match(/\{/g) || []).length;
    count++; if (rules < 50) { fails++; print(`  FAIL: real stylesheet: only ${rules} accent rules`); }
    lacks(o, '-st-accent', 'real stylesheet: no accent keyword left');
    lacks(recolor(real, '#ff40a0', '#ffffff'), '-st-accent', 'real stylesheet recoloured: no accent keyword left');
}
print(`accent_test.js: ${count} assertions, ${fails} failed`);
if (fails) imports.system.exit(1);
