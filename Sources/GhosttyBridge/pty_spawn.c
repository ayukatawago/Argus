#include <util.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <pwd.h>

// Spawns `shell` with a PTY. Returns the master FD on success, -1 on error.
// Writes the child PID into *out_pid.
int pty_spawn(const char *shell, int *out_pid) {
    int master = -1, slave = -1;
    if (openpty(&master, &slave, NULL, NULL, NULL) != 0) {
        return -1;
    }

    int pid = fork();
    if (pid < 0) {
        close(master);
        close(slave);
        return -1;
    }

    if (pid == 0) {
        close(master);
        setsid();
        ioctl(slave, TIOCSCTTY, 0);
        dup2(slave, 0);
        dup2(slave, 1);
        dup2(slave, 2);
        if (slave > 2) close(slave);

        setenv("TERM", "xterm-256color", 1);
        setenv("COLORTERM", "truecolor", 1);

        // Change to the user's home directory. macOS apps launch with cwd="/".
        // Prefer getpwuid so this works even if HOME is absent from the env.
        const char *home = getenv("HOME");
        if (!home) {
            struct passwd *pw = getpwuid(getuid());
            if (pw) home = pw->pw_dir;
        }
        if (home) chdir(home);

        // Prefix argv[0] with '-' to signal a login shell (POSIX convention).
        const char *base = strrchr(shell, '/');
        base = base ? base + 1 : shell;
        char login_name[256];
        snprintf(login_name, sizeof(login_name), "-%s", base);
        char *argv[] = {login_name, NULL};
        execvp(shell, argv);
        _exit(127);
    }

    close(slave);
    if (out_pid) *out_pid = pid;
    return master;
}
