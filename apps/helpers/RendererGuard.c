#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/resource.h>
#include <sys/event.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

static const uint64_t job_threshold = 256ULL * 1024 * 1024;
static unsigned entries;
static pid_t group;

static void reject(const char *reason) {
    /* The launcher may have died and closed stderr. Logging must never kill
       this supervisor with SIGPIPE before its process-group cleanup runs. */
    signal(SIGPIPE, SIG_IGN);
    fprintf(stderr, "DOCVER_RESOURCE_LIMIT: %s\n", reason);
    fflush(stderr);
    /* The launcher must own this detached group before any child is started. */
    killpg(group, SIGKILL);
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

/* The untrusted converter must remain the detached session leader. A session
   leader cannot move process groups or create a new session; its sandbox also
   denies fork. The trusted monitor is a child in that same owned group. */
int main(int argc, char **argv) {
    signal(SIGPIPE, SIG_IGN);
    group = getpid();
    if (argc < 4 || getpgrp() != group || getsid(0) != group || fcntl(3, F_GETFD) < 0) {
        fputs("Renderer guard requires a detached session and status pipe\n", stderr);
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
    int ready[2];
    if (pipe(ready)) return 5;
    pid_t monitor = fork();
    if (monitor < 0) return 5;
    if (monitor > 0) {
        close(3); /* Monitor exclusively owns the status channel from this point. */
        close(ready[1]);
        char ack = 0;
        ssize_t count;
        do { count = read(ready[0], &ack, 1); } while (count < 0 && errno == EINTR);
        if (count != 1 || ack != 'R') reject("Monitor startup failed");
        close(ready[0]);
        close(root);
        execv(argv[2], argv + 2);
        reject("Converter exec failed");
    }
    close(ready[0]);
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    int queue = kqueue();
    if (queue < 0) reject("Monitor event queue failed");
    struct kevent changes[2];
    EV_SET(&changes[0], launcher, EVFILT_PROC, EV_ADD | EV_ENABLE | EV_RECEIPT, NOTE_EXIT, 0, NULL);
    EV_SET(&changes[1], group, EVFILT_PROC, EV_ADD | EV_ENABLE | EV_RECEIPT, NOTE_EXIT, 0, NULL);
    struct kevent receipts[2];
    if (kevent(queue, changes, 2, receipts, 2, NULL) != 2) reject("Monitor registration failed");
    for (int i = 0; i < 2; i++)
        if (!(receipts[i].flags & EV_ERROR) || receipts[i].data != 0) reject("Monitor registration refused");
    char header[64];
    int length = snprintf(header, sizeof(header), "M %d\n", getpid());
    if (write(3, header, (size_t)length) != length || write(ready[1], "R", 1) != 1)
        reject("Launcher status channel closed");
    close(ready[1]);
    const struct timespec interval = {0, 50000000};
    for (;;) {
        struct kevent events[2];
        int count = kevent(queue, NULL, 0, events, 2, &interval);
        if (count < 0) { if (errno == EINTR) continue; reject("Monitor event wait failed"); }
        int finished = 0;
        for (int i = 0; i < count; i++) {
            if ((events[i].flags & EV_ERROR) || (pid_t)events[i].ident == launcher)
                reject("Launcher exited during conversion");
            if ((pid_t)events[i].ident == group && (events[i].fflags & NOTE_EXIT)) finished = 1;
        }
        entries = 0;
        directory_size(root, 0);
        if (finished) {
            /* Success is provisional: the launcher also requires converter exit0. */
            if (write(3, "OK\n", 3) != 3) reject("Launcher status channel closed");
            close(root);
            close(queue);
            close(3);
            return 0;
        }
    }
}
