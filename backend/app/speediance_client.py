"""Acceso a Speediance a través de la librería no oficial `speediance`."""
from __future__ import annotations

from .config import Settings


def check_speediance(settings: Settings) -> None:
    """Verifica que el login contra Speediance funciona. Lanza excepción si no."""
    from speediance import Credentials, SpeedianceClient

    with SpeedianceClient(
        Credentials(email=settings.email, password=settings.password, region=settings.region)
    ) as client:
        client.login()
