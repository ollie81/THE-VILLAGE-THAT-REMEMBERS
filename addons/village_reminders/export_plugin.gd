@tool
extends EditorExportPlugin
## The daily reminder (android_plugin/, compiled into the Gradle build):
## the notification permission, the receiver that shows the reminder, and
## the Godot plugin entry that makes `VillageNotify` available to scripts.


func _get_name() -> String:
	return "VillageReminders"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _get_android_manifest_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	return '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />'


func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	return """
	<receiver android:name="com.ollie81.village.ReminderReceiver" android:exported="false" />
	<meta-data android:name="org.godotengine.plugin.v2.VillageNotify" android:value="com.ollie81.village.VillageNotify" />
	"""
