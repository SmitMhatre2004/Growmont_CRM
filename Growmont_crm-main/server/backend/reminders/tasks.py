from celery import shared_task
from django.core.mail import EmailMultiAlternatives
from django.utils import timezone
from django.conf import settings
from datetime import timedelta
from core.models import Reminder, Employee


def build_email_html(reminder, employee):
    type_label = "🏢 Corporate Event" if reminder.type == "CORPORATE" else "👤 Personal Event"
    priority_colors = {
        "HIGH": "#FF4444",
        "MEDIUM": "#FF9800",
        "LOW": "#4CAF50",
    }
    priority_color = priority_colors.get(reminder.priority, "#555555")

    # Fix 2 — NULL safe date/time
    date_str = reminder.date.strftime("%B %d, %Y") if reminder.date else "N/A"
    time_str = reminder.time.strftime("%I:%M %p") if reminder.time else "N/A"

    return f"""
    <!DOCTYPE html>
    <html>
    <head><meta charset="UTF-8"/></head>
    <body style="font-family: Arial, sans-serif; background: #f4f4f4; padding: 20px;">
      <div style="max-width: 560px; margin: auto; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1);">
        <div style="background: #00337C; padding: 24px; text-align: center;">
          <h1 style="color: white; margin: 0; font-size: 22px;">🔔 Reminder Alert</h1>
        </div>
        <div style="padding: 28px;">
          <div style="background: #FFF3CD; border: 1px solid #FFD700; border-radius: 8px; padding: 12px 16px; margin-bottom: 20px; font-size: 14px; color: #856404;">
            ⏰ <strong>This event starts in 10 minutes!</strong>
          </div>
          <p style="font-size: 12px; color: #888; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 4px;">Event Name</p>
          <p style="font-size: 16px; color: #222; font-weight: 600; margin-bottom: 16px;">{reminder.event_name}</p>
          <hr style="border: none; border-top: 1px solid #eee; margin: 16px 0;"/>
          <p style="font-size: 12px; color: #888; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 4px;">Date & Time</p>
          <p style="font-size: 16px; color: #222; font-weight: 600; margin-bottom: 16px;">📅 {date_str} &nbsp;|&nbsp; 🕐 {time_str}</p>
          <p style="font-size: 12px; color: #888; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 4px;">Type</p>
          <p style="font-size: 16px; color: #222; font-weight: 600; margin-bottom: 16px;">{type_label}</p>
          <p style="font-size: 12px; color: #888; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 4px;">Priority</p>
          <p style="margin-bottom: 16px;"><span style="display: inline-block; padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: bold; color: white; background: {priority_color};">{reminder.priority}</span></p>
          <hr style="border: none; border-top: 1px solid #eee; margin: 16px 0;"/>
          <p style="font-size: 14px; color: #555;">Hi <strong>{employee.name}</strong>, this is your scheduled reminder. Please be prepared!</p>
        </div>
        <div style="background: #f9f9f9; padding: 16px 28px; font-size: 12px; color: #aaa; text-align: center; border-top: 1px solid #eee;">
          You received this because you set a reminder on Growmont.<br/>
          © 2026 Growmont. All rights reserved.
        </div>
      </div>
    </body>
    </html>
    """


@shared_task
def send_reminder_emails():
    now = timezone.now()
    # Fix 1 — use localtime to avoid timezone mismatch
    target_time = timezone.localtime(now + timedelta(minutes=10))

    reminders = Reminder.objects.filter(
        is_sent=False,
        date=target_time.date(),
        time__gte=(target_time - timedelta(seconds=30)).time(),
        time__lte=(target_time + timedelta(seconds=30)).time(),
    ).select_related('employee')

    for reminder in reminders:
        employee = reminder.employee
        if not employee.email:
            continue

        html_content = build_email_html(reminder, employee)
        subject = f"⏰ Reminder: {reminder.event_name} starts in 10 minutes!"

        msg = EmailMultiAlternatives(
            subject=subject,
            body=f"Reminder: {reminder.event_name} at {reminder.time} on {reminder.date}",
            from_email=settings.DEFAULT_FROM_EMAIL,  # Fix 3 — proper from_email
            to=[employee.email],
        )
        msg.attach_alternative(html_content, "text/html")
        msg.send()

        # Fix 4 — atomic update to prevent duplicate emails
        reminder.is_sent = True
        reminder.save(update_fields=["is_sent"])