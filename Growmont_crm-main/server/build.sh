#!/usr/bin/env bash
# exit on error
# set -o errexit

# pip install -r requirements.txt

# python manage.py collectstatic --no-input
# python manage.py migrate

#!/usr/bin/env bash
# exit on error
set -o errexit

# Install dependencies
pip install -r requirements.txt

# Collect static files
python manage.py collectstatic --no-input --clear

# Run database migrations
python manage.py migrate --no-input

# gunicorn backend.wsgi:application --bind 0.0.0.0:$PORT --timeout 120 --workers 2 --threads 2 --worker-class sync --max-requests 1000 --max-requests-jitter 50