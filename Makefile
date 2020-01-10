CC ?= gcc
CFLAGS += -Wall -Wextra

bin := eib

$(bin): eib.c
	$(CC) $^ -o $@ $(CFLAGS)

clean:
	rm -f $(bin)

.PHONY: clean
