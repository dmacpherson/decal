/* Double-clickable launcher: runs Decal/decal-me.sh next to it (or decal-me.sh beside it); the script opens a terminal. */
#include <limits.h>
#include <libgen.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
  char exe[PATH_MAX], script[PATH_MAX + 16];
  ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
  if (n < 0) { perror("readlink"); return 1; }
  exe[n] = 0;
  char *dir = dirname(exe);
  snprintf(script, sizeof script, "%s/Decal/decal-me.sh", dir);
  if (access(script, R_OK) != 0) snprintf(script, sizeof script, "%s/decal-me.sh", dir);
  execl("/bin/bash", "bash", script, (char *)0);
  execlp("bash", "bash", script, (char *)0);
  perror("bash");
  return 1;
}
