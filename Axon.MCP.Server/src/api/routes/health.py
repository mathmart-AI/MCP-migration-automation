import asyncio

from fastapi import APIRouter, Response

from src.config.settings import get_settings


router = APIRouter()


@router.get("/health")
async def health_check() -> dict[str, str]:
    """Basic health check endpoint."""
    return {
        "status": "healthy",
        "service": get_settings().app_name,
        "version": get_settings().app_version,
        "environment": get_settings().environment,
    }


@router.get("/health/ready")
async def readiness_check() -> dict[str, str]:
    """
    Readiness probe for Kubernetes.
    Checks if service is ready to accept traffic.
    """
    return {"status": "ready"}


@router.get("/health/live")
async def liveness_check() -> dict[str, str]:
    """
    Liveness probe for Kubernetes.
    Checks if service is alive (not deadlocked).
    """
    return {"status": "alive"}


@router.get("/metrics")
async def metrics():
    """
    Prometheus metrics endpoint.
    Disabled for zero-egress architecture.
    """
    return {"status": "metrics disabled"}


