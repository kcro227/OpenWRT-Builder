# scripts/menu/Makefile

CC = gcc
CFLAGS = -Wall -O2
TARGET = menu

all: $(TARGET)

$(TARGET): menu.c
	@$(CC) $(CFLAGS) -o $(TARGET) menu.c

clean:
	@rm -f $(TARGET)

.PHONY: all clean