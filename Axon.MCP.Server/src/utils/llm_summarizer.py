"""
LLM Summarizer - ZERO EGRESS MODE
All external LLM calls have been permanently removed.
Only the heuristic fallback summarizer remains. No network traffic to
any external provider (OpenAI, OpenRouter, Ollama, etc.).
"""

from typing import Dict, List, Optional

from src.utils.logging_config import get_logger
from src.utils.module_identifier import ModuleInfo

logger = get_logger(__name__)


class LLMSummarizer:
    """Generate heuristic summaries of code modules (Zero Egress — no external LLM)."""

    def __init__(self, provider: str = None, model: str = None):
        """Initialize summarizer. All parameters are ignored (Zero Egress)."""
        self.provider = "disabled"
        self.model = "disabled"
        logger.info("LLMSummarizer initialized in ZERO EGRESS mode — no external LLM calls")

    async def summarize_module(
        self,
        module_info: ModuleInfo,
        symbol_list: List[Dict],
        file_contents: Optional[Dict[str, str]] = None,
    ) -> Optional[Dict]:
        """
        Generate a heuristic-based summary of a module.

        Args:
            module_info: Module information
            symbol_list: List of key symbols in the module
            file_contents: Ignored in Zero Egress mode

        Returns:
            Dictionary with functional_summary, business_purpose, key_components, etc.
        """
        return self._generate_fallback_summary(module_info, symbol_list)

    async def summarize_async(self, prompt: str) -> Optional[str]:
        """Return a static disabled response (Zero Egress)."""
        return '{"functional_summary": "LLM Disabled", "business_purpose": "Zero Egress — no external calls"}'

    def _generate_fallback_summary(
        self, module_info: ModuleInfo, symbol_list: List[Dict]
    ) -> Dict:
        """Generate a simple heuristic-based summary from structural analysis."""
        primary_lang = (
            max(module_info.languages.items(), key=lambda x: x[1])[0]
            if module_info.languages
            else "unknown"
        )

        summary_parts = []

        if module_info.is_package:
            summary_parts.append(
                f"A {primary_lang} package containing {module_info.file_count} files"
            )
        else:
            summary_parts.append(
                f"A directory containing {module_info.file_count} {primary_lang} files"
            )

        if module_info.symbol_count > 0:
            summary_parts.append(
                f"with {module_info.symbol_count} code symbols ({module_info.line_count} lines)"
            )

        summary = ". ".join(summary_parts) + "."

        key_components = []
        for symbol in symbol_list[:10]:
            key_components.append(
                {
                    "name": symbol["name"],
                    "description": symbol.get("documentation", "")[:100] or "No description",
                    "type": symbol["kind"],
                }
            )

        return {
            "functional_summary": summary,
            "business_purpose": f"Module at {module_info.path}",
            "key_components": key_components,
            "dependencies": {"internal": [], "external": []},
            "complexity_score": min(10, max(1, module_info.file_count // 2)),
            "use_cases": [],
        }

