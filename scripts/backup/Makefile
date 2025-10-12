# 编译器设置
CC = gcc
CFLAGS = -Wall -Wextra -std=c99 -D_POSIX_C_SOURCE=200809L -D_GNU_SOURCE
LDFLAGS = -L../utils -lutils
TARGET = backup
SRCDIR = .
OBJDIR = .

# 源文件
SOURCES = $(SRCDIR)/backup.c
OBJECTS = $(SOURCES:$(SRCDIR)/%.c=$(OBJDIR)/%.o)

# 默认构建
all: $(TARGET)

# 链接目标文件
$(TARGET): $(OBJECTS)
	@$(CC) $(CFLAGS) $(OBJECTS) -o $@ $(LDFLAGS)

# 编译源文件
$(OBJDIR)/%.o: $(SRCDIR)/%.c
	@echo CC $<
	@$(CC) $(CFLAGS) -c $< -o $@

# 清理生成的文件
clean:
	rm -f $(OBJECTS) $(TARGET)

.PHONY: all clean