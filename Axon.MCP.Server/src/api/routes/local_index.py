"""Local indexing API route for Tree-sitter analysis of mounted directories.

This provides a lightweight, stateless endpoint that scans local directories
using the existing parser infrastructure, without requiring GitLab, Celery,
or database writes. Designed for the /CONTEXT volume mount scenario.
"""

import os
from pathlib import Path
from typing import List, Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from src.utils.logging_config import get_logger

logger = get_logger(__name__)

router = APIRouter()


# ── Request / Response Models ─────────────────────────────────────────────────

class ScanRequest(BaseModel):
    """Request body for local directory scanning."""
    paths: List[str]
    extensions: Optional[List[str]] = None  # e.g. [".go", ".py", ".tsx"]
    max_files: int = 500


class FileResult(BaseModel):
    """Result for a single parsed file."""
    path: str
    language: str
    symbols_count: int
    symbols: List[str]  # First N symbol names
    size_bytes: int


class ScanResponse(BaseModel):
    """Response from a local directory scan."""
    total_files_scanned: int
    total_symbols_found: int
    results: List[FileResult]
    errors: List[str]


# ── Language detection ────────────────────────────────────────────────────────

EXTENSION_TO_LANGUAGE = {
    ".py": "python",
    ".go": "go",
    ".js": "javascript",
    ".jsx": "javascript",
    ".ts": "typescript",
    ".tsx": "typescript",
    ".cs": "csharp",
    ".java": "java",
    ".rs": "rust",
    ".rb": "ruby",
    ".yaml": "yaml",
    ".yml": "yaml",
    ".json": "json",
    ".toml": "toml",
    ".md": "markdown",
    ".vue": "vue",
    ".sql": "sql",
    ".sh": "shell",
    ".bash": "shell",
    ".dockerfile": "dockerfile",
    ".tf": "terraform",
    ".hcl": "terraform",
}

# Default extensions to scan if none specified
DEFAULT_EXTENSIONS = {".go", ".py", ".js", ".jsx", ".ts", ".tsx", ".cs", ".java", ".yaml", ".yml", ".vue"}


def detect_language(file_path: str) -> Optional[str]:
    """Detect the language of a file from its extension."""
    ext = Path(file_path).suffix.lower()
    # Special case for Dockerfile (no extension)
    if Path(file_path).name.lower() in ("dockerfile", "containerfile"):
        return "dockerfile"
    return EXTENSION_TO_LANGUAGE.get(ext)


# ── Tree-sitter symbol extraction (lightweight) ──────────────────────────────

def extract_symbols_lightweight(file_path: str, language: str) -> List[str]:
    """
    Extract symbol names from a file using simple regex-based heuristics.
    This is a lightweight alternative to full Tree-sitter parsing that works
    without database dependencies.
    """
    import re

    symbols = []
    try:
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
    except Exception:
        return symbols

    patterns = {
        "go": [
            (r"^func\s+(?:\([^)]+\)\s+)?(\w+)\s*\(", "func"),
            (r"^type\s+(\w+)\s+(?:struct|interface)\b", "type"),
        ],
        "python": [
            (r"^(?:async\s+)?def\s+(\w+)\s*\(", "def"),
            (r"^class\s+(\w+)", "class"),
        ],
        "javascript": [
            (r"(?:export\s+)?(?:async\s+)?function\s+(\w+)", "function"),
            (r"(?:export\s+)?class\s+(\w+)", "class"),
            (r"(?:export\s+)?const\s+(\w+)\s*=\s*(?:\([^)]*\)|[^=])*=>", "arrow"),
        ],
        "typescript": [
            (r"(?:export\s+)?(?:async\s+)?function\s+(\w+)", "function"),
            (r"(?:export\s+)?class\s+(\w+)", "class"),
            (r"(?:export\s+)?interface\s+(\w+)", "interface"),
            (r"(?:export\s+)?type\s+(\w+)\s*=", "type"),
            (r"(?:export\s+)?const\s+(\w+)\s*=\s*(?:\([^)]*\)|[^=])*=>", "arrow"),
        ],
        "csharp": [
            (r"\b(?:public|private|protected|internal)\s+(?:static\s+)?(?:async\s+)?[\w<>\[\],\s]+\s+(\w+)\s*\(", "method"),
            (r"\b(?:public|private|internal)\s+(?:partial\s+)?class\s+(\w+)", "class"),
            (r"\b(?:public|private|internal)\s+interface\s+(\w+)", "interface"),
        ],
        "java": [
            (r"\b(?:public|private|protected)\s+(?:static\s+)?[\w<>\[\],\s]+\s+(\w+)\s*\(", "method"),
            (r"\b(?:public|private)\s+(?:abstract\s+)?class\s+(\w+)", "class"),
            (r"\b(?:public|private)\s+interface\s+(\w+)", "interface"),
        ],
        "yaml": [
            (r"^(\w[\w-]*):", "key"),
        ],
    }

    lang_patterns = patterns.get(language, [])
    for pattern, _ in lang_patterns:
        for match in re.finditer(pattern, content, re.MULTILINE):
            name = match.group(1)
            if name and len(name) > 1 and name not in ("if", "for", "else", "return", "var", "let", "const"):
                symbols.append(name)

    return symbols


# ── Endpoint ──────────────────────────────────────────────────────────────────

@router.post("/local-index/scan", response_model=ScanResponse)
async def scan_local_directories(request: ScanRequest):
    """
    Scan local directories for source files and extract symbols.

    This endpoint walks the specified directories, detects programming languages,
    and extracts symbol names using lightweight regex-based parsing.
    No database or external service is required.

    Designed for the /CONTEXT volume mount: the Go proxy starts a Docker
    container with `-v ~/CONTEXT:/CONTEXT`, and this endpoint lets the
    Axon backend analyze those files on demand.
    """
    allowed_extensions = set(request.extensions) if request.extensions else DEFAULT_EXTENSIONS
    results: List[FileResult] = []
    errors: List[str] = []
    total_symbols = 0
    files_scanned = 0

    for scan_path in request.paths:
        if not os.path.exists(scan_path):
            errors.append(f"Path does not exist: {scan_path}")
            continue

        if not os.path.isdir(scan_path):
            errors.append(f"Path is not a directory: {scan_path}")
            continue

        # Walk the directory tree
        for root, dirs, files in os.walk(scan_path):
            # Skip hidden directories and common non-source directories
            dirs[:] = [
                d for d in dirs
                if not d.startswith(".")
                and d not in ("node_modules", "__pycache__", "vendor", ".git", "dist", "build", "bin", "obj")
            ]

            for filename in files:
                if files_scanned >= request.max_files:
                    break

                file_path = os.path.join(root, filename)
                ext = Path(filename).suffix.lower()

                if ext not in allowed_extensions:
                    continue

                language = detect_language(file_path)
                if not language:
                    continue

                try:
                    file_size = os.path.getsize(file_path)
                    # Skip very large files (> 1MB)
                    if file_size > 1_000_000:
                        continue

                    symbols = extract_symbols_lightweight(file_path, language)
                    files_scanned += 1
                    total_symbols += len(symbols)

                    results.append(FileResult(
                        path=file_path,
                        language=language,
                        symbols_count=len(symbols),
                        symbols=symbols[:50],  # Cap at 50 symbol names per file
                        size_bytes=file_size,
                    ))
                except Exception as e:
                    errors.append(f"Error processing {file_path}: {str(e)}")

            if files_scanned >= request.max_files:
                errors.append(f"Reached max_files limit ({request.max_files}). Scan truncated.")
                break

    logger.info(
        "local_index_scan_completed",
        paths=request.paths,
        files_scanned=files_scanned,
        total_symbols=total_symbols,
        errors_count=len(errors),
    )

    return ScanResponse(
        total_files_scanned=files_scanned,
        total_symbols_found=total_symbols,
        results=results,
        errors=errors,
    )
