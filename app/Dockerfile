# =============================================================================
# Dockerfile for ML Prediction API
# =============================================================================
#
# BUILD & PUSH TO ECR:
#   ECR_URL=$(terraform -chdir=terraform output -raw ecr_repository_url)
#   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL
#   docker build -t $ECR_URL:v1 ./app/
#   docker push $ECR_URL:v1
# =============================================================================

FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Copy requirements first for Docker layer caching optimization
COPY requirements.txt .
RUN pip install --no-cache-dir --no-compile -r requirements.txt

COPY app.py .

# Non-root user for security (K8s PodSecurityPolicy best practice)
RUN adduser --disabled-password --gecos "" --no-create-home appuser
USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/')" || exit 1

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
