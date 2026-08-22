.PHONY: build test check package install clean

build:
	swift build --target MomentMonitorCore

test:
	swift test

check:
	./Scripts/check_read_only.sh

package:
	./Scripts/package_app.sh

install:
	./Scripts/install_app.sh

clean:
	rm -rf .build dist
