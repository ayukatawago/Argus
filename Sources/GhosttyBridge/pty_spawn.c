#include <util.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <pwd.h>

// Spawns `shell` with a PTY. Returns the master FD on success, -1 on error.
// Writes the child PID into *out_pid.
// working_dir sets the child's cwd; pass NULL to use the user's home directory.
int pty_spawn(const char *shell, const char *working_dir, int *out_pid) {
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

        // Use the requested working_dir, or fall back to the user's home directory.
        // Prefer getpwuid for home so this works even when HOME is absent from env.
        const char *dir = working_dir;
        if (!dir || dir[0] == '\0') {
            dir = getenv("HOME");
            if (!dir) {
                struct passwd *pw = getpwuid(getuid());
                if (pw) dir = pw->pw_dir;
            }
        }
        if (dir) chdir(dir);

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
