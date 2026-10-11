# Базовый образ содержит Python. Digest можно зафиксировать после выбора платформы.
FROM python:3.12-slim
# Все последующие команды выполняются в /app.
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
# Зависимости меняются реже кода: их слой можно использовать повторно.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
# HTTP-сервис работает без root.
RUN useradd --uid 10001 --create-home appuser
COPY --chown=10001:10001 app.py .
USER 10001:10001
# EXPOSE описывает порт, публикацию задаём в docker run или Compose.
EXPOSE 8080
# Exec-форма передаёт сигналы непосредственно процессу Python.
CMD ["python", "app.py"]
