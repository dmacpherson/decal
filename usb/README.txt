decal on a USB stick
====================

Double-click "Decal" (next to this folder) on any Linux PC: a terminal opens, decal installs (or updates), your
profile is fetched, and decal's menu opens. Nothing changes until you choose Apply in the menu.

  Profile:   {profile}
  decal:     {version}
  Made:      {made}

ARM machines (Raspberry Pi, Snapdragon laptops, Apple Silicon with Linux): double-click Decal-ARM in this folder,
if it's here (made with "Also for ARM machines"). Anywhere, from a terminal:  bash .Decal/start.sh

This folder is hidden: Ctrl+H shows it in most file managers.

The file "key" (if there is one) can only read your profile repo. If this stick is lost, revoke it on GitHub:
Settings -> Applications -> Decal Profile -> Revoke (or delete the token you made).

Save this machine (in the stick's menu) stamps the PC you're on back to your profile: to the copy on this stick,
your GitHub repo, or anywhere else. Saving to GitHub signs in each time the menu opens (a key that can write is
never kept on the stick, and lasts 8 hours at most).

To change anything on this stick: run decal usb on your own machine with the stick plugged in.
