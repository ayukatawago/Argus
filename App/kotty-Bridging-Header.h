#pragma once

// C PTY spawn helper — fork()/openpty() are unavailable in Swift.
int pty_spawn(const char *shell, int *out_pid);
