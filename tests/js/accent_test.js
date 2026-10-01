// gjs -m tests/js/accent_test.js [SHELL_CSS] : unit tests for the Decal Tweaks accent stylesheet generator
import GLib from 'gi://GLib';
import {accentCss, readableFg, validColor} from '../../modules/gnome-extensions/bundled/decal@decal/tweaks/accent-css.js';

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
}
print(`accent_test.js: ${count} assertions, ${fails} failed`);
if (fails) imports.system.exit(1);
