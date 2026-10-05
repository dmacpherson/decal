/* decal USB stick launcher: double-click it. Runs .Decal/start.sh next to it (that script opens a terminal), or
 * .Decal.old's when a stick was pulled out mid-update;
 * from inside .Decal (Decal-ARM), the start.sh next to it. Without one, opens the README.
 * Built static by the release workflow: gcc -Os -static -s (musl). */
#include <libgen.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int found(char *out, size_t n, const char *dir, const char *name) {
  snprintf(out, n, "%s/.Decal/%s", dir, name);
  if (access(out, R_OK) == 0) return 1;
  snprintf(out, n, "%s/.Decal.old/%s", dir, name);   /* pulled out mid-update: the previous setup, whole */
  if (access(out, R_OK) == 0) return 1;
  snprintf(out, n, "%s/%s", dir, name);   /* the launcher is in .Decal itself */
  return access(out, R_OK) == 0;
}

int main(void) {
  char exe[PATH_MAX], path[PATH_MAX + 32];
  ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
  if (n < 0) { perror("readlink"); return 1; }
  exe[n] = 0;
  char *dir = dirname(exe);
  if (found(path, sizeof path, dir, "start.sh")) {
    execl("/bin/bash", "bash", path, (char *)0);
    execlp("bash", "bash", path, (char *)0);
    perror("bash");
    return 1;
  }
  if (found(path, sizeof path, dir, "README.txt")) {
    execlp("xdg-open", "xdg-open", path, (char *)0);
    perror("xdg-open");
  }
  return 1;
}
