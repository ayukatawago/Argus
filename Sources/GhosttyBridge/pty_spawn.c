#include <util.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/ioctl.h>

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

        char *argv[] = {(char *)shell, NULL};
        execvp(shell, argv);
        _exit(127);
    }

    close(slave);
    if (out_pid) *out_pid = pid;
    return master;
}
