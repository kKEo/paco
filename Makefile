build:
	xcodebuild -project PaCo.xcodeproj -scheme PaCo -destination "platform=macOS" build

clear-pin:
	security delete-generic-password -s "com.paco.pin.hash" 2>/dev/null
	security delete-generic-password -s "com.paco.pin.salt" 2>/dev/null
