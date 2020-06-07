FROM python:3.8.2-slim-buster
RUN apt update && apt install --yes git gcc
ENV \
    PYTHONPATH=sampleapp \
    DJANGO_SETTINGS_MODULE=sampleapp.settings.base
RUN pip install poetry
WORKDIR /app
COPY poetry.lock pyproject.toml /app/
RUN poetry config virtualenvs.create false
RUN poetry install --no-interaction
COPY ./sampleapp /app/sampleapp
CMD poetry run gunicorn --workers=2 --bind 0.0.0.0:8000 sampleapp.wsgi
