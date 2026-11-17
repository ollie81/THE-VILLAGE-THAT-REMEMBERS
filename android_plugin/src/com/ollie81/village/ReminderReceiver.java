package com.ollie81.village;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

/** Shows the reminder when its time comes; tapping it opens the game. */
public class ReminderReceiver extends BroadcastReceiver {
	static final String EXTRA_ID = "village_id";
	static final String EXTRA_TITLE = "village_title";
	static final String EXTRA_TEXT = "village_text";
	static final String CHANNEL = "village_reminders";

	@Override
	public void onReceive(Context context, Intent intent) {
		NotificationManager nm = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
		if (nm == null) {
			return;
		}
		int id = intent.getIntExtra(EXTRA_ID, 1);
		String title = intent.getStringExtra(EXTRA_TITLE);
		String text = intent.getStringExtra(EXTRA_TEXT);
		Notification.Builder builder;
		if (Build.VERSION.SDK_INT >= 26) {
			NotificationChannel channel = new NotificationChannel(CHANNEL, "Daily reminder", NotificationManager.IMPORTANCE_DEFAULT);
			channel.setDescription("A gentle reminder when your daily gift is ready (at most once a day).");
			nm.createNotificationChannel(channel);
			builder = new Notification.Builder(context, CHANNEL);
		} else {
			builder = new Notification.Builder(context);
		}
		Intent open = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
		if (open != null) {
			open.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
			int immutable = Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0;
			builder.setContentIntent(PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT | immutable));
		}
		builder.setSmallIcon(context.getApplicationInfo().icon)
				.setContentTitle(title != null ? title : "The Village That Remembers")
				.setContentText(text != null ? text : "")
				.setStyle(new Notification.BigTextStyle().bigText(text != null ? text : ""))
				.setAutoCancel(true);
		nm.notify(id, builder.build());
	}
}
