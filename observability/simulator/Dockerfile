# STOA Metrics Simulator
# Generates realistic demo traffic for Grafana dashboards

FROM python:3.12-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy simulator
COPY simulator.py .

# Health check
HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:9091/health')" || exit 1

# Run
EXPOSE 9091
CMD ["python", "-u", "simulator.py"]
