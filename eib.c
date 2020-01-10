#define _GNU_SOURCE /* for clone and CLONE_* flags */

#include <assert.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

#include <linux/futex.h>
#include <linux/limits.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>

/* prevent the child process from using setgroups() for security */
static void deny_setgroups(pid_t pid)
{
	char path[PATH_MAX];
	ssize_t wrc;
	int fd;
	int rc;

	rc = snprintf(path, sizeof(path), "/proc/%u/setgroups", pid);
	assert(rc > 0);

	fd = open(path, O_WRONLY);
	if (fd < 0) {
		/*
		 * /proc/PID/setgroups might not exist on some systems, in which
		 * case this is not needed
		 */
		if (errno == ENOENT)
			return;
		else
			err(EXIT_FAILURE, "open: %s", path);

	}

	wrc = write(fd, "deny", 4);
	if (wrc != 4)
		err(EXIT_FAILURE, "write: %s", path);

	close(fd);
}

static void update_id_map(const char *fmt, pid_t pid, unsigned id)
{
	char path[PATH_MAX];
	FILE *fp;
	int rc;

	rc = snprintf(path, sizeof(path), fmt, pid);
	assert(rc > 0);

	fp = fopen(path, "w");
	if (fp == NULL)
		err(EXIT_FAILURE, "fopen: %s", path);
	rc = fprintf(fp, "0 %u 1", id);
	if (rc < 0)
		err(EXIT_FAILURE, "fprintf: %s", path);
	rc = fclose(fp);
	if (rc < 0)
		err(EXIT_FAILURE, "fclose: %s", path);
}

/* map uid/gid between root and current user for the given pid */
static void update_id_maps(uid_t pid)
{
	update_id_map("/proc/%u/uid_map", pid, getuid());
	deny_setgroups(pid);
	update_id_map("/proc/%u/gid_map", pid, getgid());
}

/* clone() requires a new stack for the child */
static char stack[1024*1024];

/* anonymous shared mapping between parent and child, for futex() */
static int32_t *lock;

static int futex(int op, int val)
{
	return syscall(SYS_futex, lock, op, val, NULL, 0, 0);
}

static int child_fn(void *arg)
{
	char * const *argv = arg;

	do {
		futex(FUTEX_WAIT, 0);
		/* futex may have spurious wakeups; double check here */
	} while (__atomic_load_n(lock, __ATOMIC_SEQ_CST) == 0);

	execvp("bash", argv);
	/* execvp only returns on failure */
	err(EXIT_FAILURE, "execvp");
}

int main(int argc, const char * const argv[])
{
	pid_t child_pid;
	pid_t rc;
	int status;

	(void)argc;

	/*
	 * clone() will create a private mapping of the process memory space; in
	 * order to share the futex between the parent and child, we make a
	 * shared anonymous mapping
	 */
	lock = mmap(NULL, sizeof(*lock), PROT_READ | PROT_WRITE,
		    MAP_ANONYMOUS | MAP_SHARED, -1, 0);
	if (lock == MAP_FAILED)
		err(EXIT_FAILURE, "mmap");

	child_pid = clone(child_fn, stack + sizeof(stack),
			  CLONE_NEWNS | CLONE_NEWUSER | CLONE_NEWPID | SIGCHLD,
			  (void *)&argv[1]);
	if (child_pid == -1)
		err(EXIT_FAILURE, "clone");

	update_id_maps(child_pid);

	__atomic_store_n(lock, 1, __ATOMIC_SEQ_CST);
	futex(FUTEX_WAKE, 1);

	/*
	 * wait for the child and propagate its exit status to make this appear
	 * as if it was one process
	 */
	rc = waitpid(child_pid, &status, 0);
	if (rc == -1)
		err(EXIT_FAILURE, "waitpid");

	if (WIFEXITED(status))
		return WEXITSTATUS(status);
	else
		return EXIT_FAILURE;
}
