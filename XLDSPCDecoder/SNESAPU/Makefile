TARGET = snesapudec
ASM_SOURCES = APU.asm DSP.asm SPC700.asm
ASM_OBJS = $(ASM_SOURCES:.asm=.o)
ASM_OBJS := $(addprefix i386/,$(ASM_OBJS))
SOURCES = snesapudec.c
OBJS = $(SOURCES:.c=.o)
OBJS := $(addprefix i386/,$(OBJS))

CC = clang -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) -arch i386 -isysroot $(SDKROOT)
CFLAGS = -O2
NASMFLAGS = -f macho -DCDECL


all : $(TARGET)
$(TARGET) : $(ASM_OBJS) $(OBJS)
	$(CC) -Wl,-no_pie -o $@ $^

i386/%.o: %.asm
	@if [ ! -d i386 ]; then \
		echo "mkdir -p i386"; mkdir -p i386; \
    fi
	nasm $(NASMFLAGS) -o $@ $<
	
i386/%.o: %.c
	@if [ ! -d i386 ]; then \
		echo "mkdir -p i386"; mkdir -p i386; \
    fi
	$(CC) $(CFLAGS) -c $< -o $@

clean :
	rm -f $(ASM_OBJS) $(OBJS) $(TARGET)
