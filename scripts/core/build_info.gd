class_name BuildInfo
extends RefCounted
## Which build this is. CI writes the commit and date here before exporting
## the APK, so a phone's "Report a problem" screen says exactly which code it
## is running. Local runs say "dev".

const COMMIT := "dev"
const BUILT := ""


static func text() -> String:
	var version := String(ProjectSettings.get_setting("application/config/version", ""))
	return "v%s (%s%s)" % [version, COMMIT, ", " + BUILT if BUILT != "" else ""]
