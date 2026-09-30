# Thin wrapper around ./decal
default:
    @./decal list
list:
    @./decal list
status *mods:
    @./decal status {{mods}}
add +mods:
    @./decal add {{mods}}
remove +mods:
    @./decal remove {{mods}}
capture mod:
    @./decal capture {{mod}}
