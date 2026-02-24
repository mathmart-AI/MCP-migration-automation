"""
Embedding Generator - ZERO EGRESS MODE
All external API calls (OpenAI, etc.) are permanently disabled.
Embeddings are either local or stubbed for the Zero Egress architecture.
"""
from typing import List, Dict, Optional, Any
from dataclasses import dataclass
import asyncio
import time

# ZERO EGRESS: OpenAI import permanently removed.
# No external embedding providers are used in this architecture.
OPENAI_AVAILABLE = False

from src.config.settings import get_settings
from src.utils.logging_config import get_logger
from src.utils.metrics import embedding_generation_duration, embeddings_generated_total

logger = get_logger(__name__)


@dataclass
class EmbeddingResult:
    """Result of embedding generation."""
    chunk_id: int
    vector: List[float]
    model_name: str
    model_version: str
    dimension: int


class EmbeddingGenerator:
    """Generates vector embeddings using local models only (Zero Egress)."""
    
    def __init__(self):
        """Initialize embedding generator. External providers permanently disabled."""
        # Force local provider regardless of settings for Zero Egress compliance
        self.provider = "local"
        self.model_name = "disabled"
        self.dimension = 1536
        
        logger.info(
            "embedding_generator_initialized_zero_egress",
            provider=self.provider,
            model=self.model_name,
            dimension=self.dimension,
            note="External LLM providers permanently disabled"
        )
    
    async def generate_embeddings(
        self,
        chunks: List[Dict[str, Any]],
        batch_size: Optional[int] = None
    ) -> List[EmbeddingResult]:
        """
        Generate embeddings for chunks.
        
        Args:
            chunks: List of dicts with 'id' and 'content' keys
            batch_size: Batch size for processing
            
        Returns:
            List of EmbeddingResults (empty list in Zero Egress mode)
        
        Note:
            In Zero Egress mode, embeddings are not generated externally.
            Tree-sitter structural analysis is used instead.
        """
        logger.info(
            "embedding_generation_skipped_zero_egress",
            chunk_count=len(chunks),
            reason="External LLM providers disabled"
        )
        # Return empty list — structural analysis via Tree-sitter replaces embeddings
        return []
    
    async def generate_single_embedding(self, text: str) -> List[float]:
        """
        Generate embedding for a single text.
        
        Returns:
            Empty list in Zero Egress mode.
        """
        logger.info("single_embedding_skipped_zero_egress")
        return []
