"""
=============================================================================
ML Model Prediction API — Mock Service for Canary Deployment Demo
=============================================================================

PURPOSE:
    This FastAPI application simulates a Machine Learning model inference API.
    It reads a MODEL_VERSION environment variable to identify itself as either
    the "stable" (v1) or "challenger" (v2) version.

WHY THIS MATTERS FOR CANARY DEPLOYMENTS:
    In a canary release, two versions of the same service run simultaneously.
    Istio routes a percentage of traffic to each version (e.g., 90% → v1, 10% → v2).
    This app's response includes the model_version field so we can verify
    which version handled each request — proving the traffic split works.

ARCHITECTURE:
    [Client] → [Istio Gateway] → [VirtualService 90/10] → [v1 pods OR v2 pods]
                                                            ↓
                                                    This app responds with
                                                    its MODEL_VERSION
=============================================================================
"""

import os
import hashlib
import logging
import time
from typing import List, Dict, Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

# =============================================================================
# CONFIGURATION
# =============================================================================
# MODEL_VERSION is injected as an environment variable by Kubernetes.
# See k8s-deployments.yaml → spec.template.spec.containers[].env
# Default is "v1" for local development without Kubernetes.
MODEL_VERSION = os.environ.get("MODEL_VERSION", "v1")

# Configure structured logging for production observability.
# In Kubernetes, these logs are collected by the cluster's logging stack
# (e.g., Fluentd → Elasticsearch → Kibana, or Loki → Grafana).
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("ml-api")

# =============================================================================
# FASTAPI APPLICATION INITIALIZATION
# =============================================================================
# The FastAPI instance is the ASGI application that uvicorn serves.
# Kubernetes probes and Istio health checks hit the endpoints defined below.
app = FastAPI(
    title="ML Prediction API",
    description="Mock ML model inference service for canary deployment demonstration",
    version=MODEL_VERSION,
    docs_url="/docs",      # Swagger UI available at /docs
    redoc_url="/redoc",    # ReDoc available at /redoc
)


# =============================================================================
# PYDANTIC MODELS (Request/Response Schemas)
# =============================================================================
# Pydantic models enforce type validation on incoming requests and
# document the API contract for consumers (and Swagger UI).

class PredictionRequest(BaseModel):
    """
    Input schema for the /predict endpoint.

    In a real ML system, 'features' would be the numerical feature vector
    extracted from raw data (e.g., user behavior, sensor readings).
    """
    features: List[float] = Field(
        ...,
        min_length=1,
        description="List of numerical features for model inference",
        examples=[[1.5, 2.3, 4.7, 0.8]],
    )


class PredictionResponse(BaseModel):
    """
    Output schema for the /predict endpoint.

    model_version: Identifies which deployed version handled this request.
                   Critical for verifying canary traffic split in Kiali/Grafana.
    prediction:    The model's output (mocked here with deterministic hashing).
    confidence:    How confident the model is in its prediction (0.0 to 1.0).
    status:        "success" or "error" — standard API response pattern.
    """
    model_version: str
    prediction: float
    confidence: float
    status: str


class HealthResponse(BaseModel):
    """Health check response used by Kubernetes probes and Istio."""
    status: str
    model_version: str
    uptime_seconds: float


# =============================================================================
# APPLICATION STATE
# =============================================================================
# Track when the app started for uptime reporting in health checks.
APP_START_TIME = time.time()


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def generate_mock_prediction(features: List[float]) -> Dict[str, Any]:
    """
    Generate a deterministic mock prediction from input features.

    WHY DETERMINISTIC?
        Using a hash ensures the same input always produces the same output,
        mimicking how a real ML model behaves (same input → same prediction).
        This makes testing and debugging reproducible.

    HOW IT WORKS:
        1. Convert features to a stable string representation
        2. SHA-256 hash the string → 64 hex chars
        3. Use first 8 hex chars as a seed for prediction value
        4. v1 and v2 intentionally produce DIFFERENT results to simulate
           a model upgrade (v2 applies a slight boost to predictions)

    Args:
        features: List of float values representing model input features.

    Returns:
        Dictionary with prediction, confidence, and status.
    """
    # Create a deterministic hash from the feature vector
    feature_string = ",".join(f"{f:.6f}" for f in features)
    hash_digest = hashlib.sha256(feature_string.encode("utf-8")).hexdigest()

    # Extract a seed from the hash (first 8 hex chars → integer)
    seed = int(hash_digest[:8], 16)

    # Generate base prediction (0.0 to 1.0 range)
    base_prediction = (seed % 10000) / 10000.0

    # =======================================================================
    # VERSION-SPECIFIC BEHAVIOR
    # v2 ("Challenger") applies a slight accuracy boost to simulate
    # a genuinely improved model. This is what you'd see in real ML:
    # the new model version should perform slightly better.
    # =======================================================================
    if MODEL_VERSION == "v2":
        # v2 boosts predictions by 5% (capped at 1.0) to simulate improvement
        prediction = min(base_prediction * 1.05, 1.0)
        confidence = 0.82 + (base_prediction * 0.15)  # Higher confidence range
    else:
        # v1 uses raw prediction
        prediction = base_prediction
        confidence = 0.75 + (base_prediction * 0.20)  # Standard confidence range

    # Cap confidence at 0.99 (no model is 100% confident)
    confidence = min(confidence, 0.99)

    return {
        "prediction": round(prediction, 4),
        "confidence": round(confidence, 4),
        "status": "success",
    }


# =============================================================================
# API ENDPOINTS
# =============================================================================

@app.get(
    "/",
    response_model=HealthResponse,
    summary="Health Check",
    description="Used by Kubernetes readiness/liveness probes and Istio health checks.",
)
def health_check() -> HealthResponse:
    """
    Health check endpoint.

    KUBERNETES PROBES:
        - readinessProbe: Checks if the pod is ready to receive traffic.
          If this fails, the pod is removed from the Service endpoints.
        - livenessProbe: Checks if the pod is alive. If this fails,
          Kubernetes restarts the container.

    Both probes hit this endpoint (see k8s-deployments.yaml).
    """
    uptime = round(time.time() - APP_START_TIME, 2)
    logger.info(f"Health check OK | version={MODEL_VERSION} | uptime={uptime}s")
    return HealthResponse(
        status="healthy",
        model_version=MODEL_VERSION,
        uptime_seconds=uptime,
    )


@app.post(
    "/predict",
    response_model=PredictionResponse,
    summary="Run Model Prediction",
    description="Submit feature vector for ML model inference. Returns prediction with confidence score.",
)
def predict(request: PredictionRequest) -> PredictionResponse:
    """
    Main prediction endpoint.

    CANARY DEPLOYMENT RELEVANCE:
        When Istio splits traffic 90/10 between v1 and v2, both versions
        receive the same type of requests. By including model_version in
        the response, we can verify in Kiali/Grafana which version handled
        each request and confirm the traffic split ratio is correct.
    """
    logger.info(
        f"Prediction request | version={MODEL_VERSION} | "
        f"num_features={len(request.features)}"
    )

    try:
        # Generate mock prediction using deterministic hashing
        result = generate_mock_prediction(request.features)

        response = PredictionResponse(
            model_version=MODEL_VERSION,
            prediction=result["prediction"],
            confidence=result["confidence"],
            status=result["status"],
        )

        logger.info(
            f"Prediction complete | version={MODEL_VERSION} | "
            f"prediction={response.prediction} | confidence={response.confidence}"
        )
        return response

    except Exception as e:
        # Log the full traceback for debugging in production
        logger.error(f"Prediction failed | version={MODEL_VERSION} | error={e}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Model inference failed: {str(e)}",
        )


# =============================================================================
# STARTUP EVENT
# =============================================================================

@app.on_event("startup")
async def startup_event():
    """
    Runs when the application starts.
    Logs configuration for debugging in Kubernetes pod logs.
    View with: kubectl logs <pod-name>
    """
    logger.info("=" * 60)
    logger.info(f"ML Prediction API Starting")
    logger.info(f"Model Version: {MODEL_VERSION}")
    logger.info(f"Docs: http://localhost:8000/docs")
    logger.info("=" * 60)


# =============================================================================
# DIRECT EXECUTION (for local development without Docker/K8s)
# =============================================================================
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
