#!/usr/bin/env bash
set -euo pipefail

python -m pip install --upgrade pip
python -m pip install -r requirements-prod.txt
python manage.py collectstatic --noinput --settings=config.settings.deploy
python manage.py migrate --noinput --settings=config.settings.deploy
