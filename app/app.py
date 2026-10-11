"""Учебный HTTP-счётчик: локальная память или Redis через Compose."""
import itertools
import os

from flask import Flask
from redis import Redis
from redis.exceptions import RedisError

app = Flask(__name__)
local_counter = itertools.count(1)
redis_host = os.getenv("REDIS_HOST")
cache = Redis(host=redis_host, decode_responses=True,
              socket_connect_timeout=2, socket_timeout=2) if redis_host else None


@app.get("/")
def index():
    try:
        visits = cache.incr("visits") if cache else next(local_counter)
    except RedisError:
        return {"error": "Redis unavailable"}, 503
    return {"visits": visits, "backend": "redis" if cache else "memory"}


@app.get("/health")
def health():
    return {"status": "ok"}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
