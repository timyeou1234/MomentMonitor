.PHONY: build test check package clean

build:
	swift build --target MomentMonitorCore

test:
	swift test

check:
	./Scripts/check_read_only.sh

package:
	./Scripts/package_app.sh

clean:
	rm -rf .build dist
