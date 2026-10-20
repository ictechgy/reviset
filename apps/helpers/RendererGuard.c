#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static const uint64_t job_threshold = 256ULL * 1024 * 1024;
static unsigned entries;
static pid_t owned_child;

static void reject(const char *reason) {
    /* The launcher may have died and closed stderr. Logging must never kill
       this supervisor with SIGPIPE before its process-group cleanup runs. */
    signal(SIGPIPE, SIG_IGN);
    fprintf(stderr, "DOCVER_RESOURCE_LIMIT: %s\n", reason);
    fflush(stderr);
    if (owned_child > 0) kill(owned_child, SIGKILL);
    /* The launcher must own this detached group before any child is started. */
    killpg(getpgrp(), SIGKILL);
    _exit(125);
}

static uint64_t directory_size(int fd, unsigned depth) {
    if (depth > 32) reject("Output directory depth limit");
    int copy = dup(fd);
    if (copy < 0) reject("Output directory descriptor limit");
    DIR *directory = fdopendir(copy);
    if (!directory) { close(copy); reject("Output directory unreadable"); }
    /* dup shares the directory offset: rewind on every monitoring pass. */
    rewinddir(directory);
    uint64_t total = 0;
    struct dirent *entry;
    errno = 0;
    while ((entry = readdir(directory))) {
        if (entry->d_name[0] == '.' && (!entry->d_name[1] ||
            (entry->d_name[1] == '.' && !entry->d_name[2]))) continue;
        if (++entries > 50000) reject("Output entry limit");
        struct stat value;
        if (fstatat(fd, entry->d_name, &value, AT_SYMLINK_NOFOLLOW)) {
            if (errno == ENOENT) { errno = 0; continue; }
            reject("Output entry unreadable");
        }
        if (S_ISLNK(value.st_mode)) reject("Output symlink refused");
        if (S_ISDIR(value.st_mode)) {
            int child = openat(fd, entry->d_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            if (child < 0) {
                if (errno == ENOENT) { errno = 0; continue; }
                reject("Output directory changed or unreadable");
            }
            total += directory_size(child, depth + 1);
            close(child);
        } else if (S_ISREG(value.st_mode) && value.st_size >= 0) {
            total += (uint64_t)value.st_size;
        } else reject("Special output file refused");
        if (total > job_threshold) reject("Aggregate256MiB job size threshold");
        errno = 0;
    }
    if (errno) reject("Output enumeration failed");
    closedir(directory);
    return total;
}

int main(int argc, char **argv) {
    signal(SIGPIPE, SIG_IGN);
    if (argc < 4 || getpgrp() != getpid()) {
        fputs("Renderer guard requires its own detached process group\n", stderr);
        return 2;
    }
    const pid_t launcher = getppid();
    if (launcher <= 1) reject("Launcher exited before supervision");
    const struct rlimit file_limit = {128ULL * 1024 * 1024, 128ULL * 1024 * 1024};
    const struct rlimit cpu_limit = {90, 90}, descriptor_limit = {256, 256};
    if (setrlimit(RLIMIT_FSIZE, &file_limit) || setrlimit(RLIMIT_CPU, &cpu_limit) ||
        setrlimit(RLIMIT_NOFILE, &descriptor_limit)) return 3;
    int root = open(argv[1], O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (root < 0) return 4;
    entries = 0;
    directory_size(root, 0);
    if (getppid() != launcher) reject("Launcher exited before conversion");
    pid_t child = fork();
    if (child < 0) { close(root); return 5; }
    if (!child) {
        close(root);
        execv(argv[2], argv + 2);
        _exit(127);
    }
    owned_child = child;
    const struct timespec interval = {0, 50000000};
    int status = 0;
    for (;;) {
        if (getppid() != launcher) reject("Launcher exited during conversion");
        const pid_t child_group = getpgid(child);
        if (child_group >= 0 && child_group != getpgrp()) reject("Child left owned process group");
        pid_t finished = waitpid(child, &status, WNOHANG);
        if (finished < 0) { if (errno == EINTR) continue; reject("Child wait failed"); }
        if (finished == child) owned_child = 0;
        entries = 0;
        directory_size(root, 0);
        if (finished == child) break;
        nanosleep(&interval, NULL);
    }
    close(root);
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return 6;
}
