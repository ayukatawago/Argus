#pragma once

// C PTY spawn helper — fork()/openpty() are unavailable in Swift.
int pty_spawn(const char *shell, const char * _Nullable working_dir, int *out_pid);
