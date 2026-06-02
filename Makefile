# MockMyCam — build tasks. `make app` then `make run` to use it.

.PHONY: dylib build test app run e2e clean

dylib:               ## Build the vendored VirtualCamera.dylib into the resource bundle
	./Scripts/build-dylib.sh

build: dylib         ## Debug build of the package
	swift build

test:                ## Run unit tests (E2E + webcam tests are gated/skipped)
	swift test

app:                 ## Assemble + adhoc-sign build/MockMyCam.app
	./Scripts/bundle-app.sh

run: app             ## Build and launch the app
	open build/MockMyCam.app

e2e:                 ## On-simulator end-to-end injection smoke test (needs a booted sim)
	./Scripts/e2e-smoke.sh

clean:
	rm -rf .build build Fixtures/SimProbe/build
	rm -f Sources/MockMyCamKit/Resources/VirtualCamera.dylib ThirdParty/VirtualCamera/VirtualCamera.dylib
