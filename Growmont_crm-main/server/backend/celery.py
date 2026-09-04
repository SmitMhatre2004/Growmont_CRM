import os
from celery import Celery

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'backend.settings')

app = Celery('backend')
app.config_from_object('django.conf:settings', namespace='CELERY')
app.autodiscover_tasks()

app.conf.beat_schedule = {
    'check-reminders-every-minute': {
        'task': 'backend.reminders.tasks.send_reminder_emails',
        'schedule': 60.0,
    },
}