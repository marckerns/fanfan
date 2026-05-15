CC = clang
CFLAGS = -Wall -Wextra -O2 -framework IOKit -framework CoreFoundation
TARGET = fanfan-smcd

all: $(TARGET)

$(TARGET): fanfan-smcd.c smc.h
	$(CC) $(CFLAGS) -o $(TARGET) fanfan-smcd.c

clean:
	rm -f $(TARGET)

.PHONY: all clean
