PATH = /usr/local/bin:/opt/local/bin:/sw/bin:/usr/bin:/bin
CC = /usr/local/bin/winegcc
CFLAGS = -m32 -O2 -mmacosx-version-min=10.4 -Wl,-syslibroot,/Developer/SDKs/MacOSX10.4u.sdk
tak_decoder: tak_decoder.c
	$(CC) $(CFLAGS) -o tak_decoder $<
	install_name_tool -change /usr/local/lib/libwine.1.dylib @executable_path/../lib/libwine.1.dylib tak_decoder.exe.so

.PHONY: clean
clean:
	rm -f tak_decoder tak_decoder.exe.so
