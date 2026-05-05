APP_NAME   = ccswitch
BINARY     = ccswitch-menubar
APP_BUNDLE = $(APP_NAME).app
SOURCES    = $(wildcard Sources/*.swift)
SWIFT      = xcrun swiftc
FLAGS      = -framework AppKit -framework ServiceManagement -framework Security

.PHONY: build install clean

build:
	$(SWIFT) $(FLAGS) $(SOURCES) -o $(BINARY)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp $(BINARY) $(APP_BUNDLE)/Contents/MacOS/
	cp Info.plist $(APP_BUNDLE)/Contents/

install: build
	cp -r $(APP_BUNDLE) /Applications/
	@echo "installed: /Applications/$(APP_BUNDLE)"
	@echo "add to Login Items in System Settings > General > Login Items"

clean:
	rm -rf $(BINARY) $(APP_BUNDLE)
