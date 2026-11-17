package com.ollie81.village;

import android.Manifest;
import android.app.Activity;
import android.app.AlarmManager;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

/** The daily reminder: schedules (and cancels) one gentle notification. */
public class VillageNotify extends GodotPlugin {
	private static final int PERMISSION_REQUEST = 4711;

	public VillageNotify(Godot godot) {
		super(godot);
	}

	@Override
	public String getPluginName() {
		return "VillageNotify";
	}

	private Context context() {
		Activity activity = getActivity();
		return activity != null ? activity.getApplicationContext() : null;
	}

	/** Whether notifications can be shown (permission granted and not switched off). */
	@UsedByGodot
	public boolean can_notify() {
		Context c = context();
		if (c == null) {
			return false;
		}
		if (Build.VERSION.SDK_INT >= 33
				&& c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
			return false;
		}
		NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
		return nm == null || Build.VERSION.SDK_INT < 24 || nm.areNotificationsEnabled();
	}

	/** Asks Android for permission to show notifications (Android 13+; earlier it's allowed). */
	@UsedByGodot
	public void request_permission() {
		final Activity activity = getActivity();
		if (activity == null || Build.VERSION.SDK_INT < 33) {
			return;
		}
		activity.runOnUiThread(new Runnable() {
			@Override
			public void run() {
				activity.requestPermissions(new String[] { Manifest.permission.POST_NOTIFICATIONS }, PERMISSION_REQUEST);
			}
		});
	}

	private PendingIntent intentFor(Context c, int id, String title, String text, int flags) {
		Intent intent = new Intent(c, ReminderReceiver.class);
		intent.putExtra(ReminderReceiver.EXTRA_ID, id);
		intent.putExtra(ReminderReceiver.EXTRA_TITLE, title);
		intent.putExtra(ReminderReceiver.EXTRA_TEXT, text);
		int immutable = Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0;
		return PendingIntent.getBroadcast(c, id, intent, flags | immutable);
	}

	/** Shows `title` / `text` in `delay_seconds` (replacing any reminder with the same id). */
	@UsedByGodot
	public void schedule(int id, String title, String text, int delay_seconds) {
		Context c = context();
		if (c == null) {
			return;
		}
		AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
		if (am == null) {
			return;
		}
		PendingIntent pi = intentFor(c, id, title, text, PendingIntent.FLAG_UPDATE_CURRENT);
		long at = System.currentTimeMillis() + Math.max(delay_seconds, 60) * 1000L;
		if (Build.VERSION.SDK_INT >= 23) {
			am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi);
		} else {
			am.set(AlarmManager.RTC_WAKEUP, at, pi);
		}
	}

	/** Cancels the reminder `id` (scheduled or already showing). */
	@UsedByGodot
	public void cancel(int id) {
		Context c = context();
		if (c == null) {
			return;
		}
		AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
		PendingIntent pi = intentFor(c, id, "", "", PendingIntent.FLAG_NO_CREATE);
		if (am != null && pi != null) {
			am.cancel(pi);
			pi.cancel();
		}
		NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
		if (nm != null) {
			nm.cancel(id);
		}
	}
}
