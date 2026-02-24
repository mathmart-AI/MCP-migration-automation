import time
from typing import List, Optional

from mcp.types import TextContent

from src.config.enums import MCPToolEnum
from src.database.session import get_async_session
from src.utils.logging_config import get_logger
from src.utils.metrics import mcp_tool_calls_total, mcp_tool_duration
from src.utils.project_mapper import ProjectMapper

logger = get_logger(__name__)

async def get_project_map(
    repository_id: int,
    max_depth: int = 2,
) -> List[TextContent]:
    """
    Get high-level project map showing modules and their relationships.

    Args:
        repository_id: Repository ID
        max_depth: Maximum depth for module mapping

    Returns:
        Project map
    """
    # Validate required parameters
    if repository_id is None:
        return [
            TextContent(
                type="text",
                text="❌ Missing required parameter: repository_id\n\n"
                "💡 Use `list_repositories()` to find available repositories and their IDs."
            )
        ]
    
    start_time = time.time()

    try:
        async with get_async_session() as session:
            mapper = ProjectMapper(session)
            project_map = await mapper.generate_project_map(
                repository_id=repository_id, max_depth=max_depth
            )

            duration = time.time() - start_time
            mcp_tool_duration.labels(tool_name=MCPToolEnum.GET_PROJECT_MAP.value).observe(
                duration
            )
            mcp_tool_calls_total.labels(
                tool_name=MCPToolEnum.GET_PROJECT_MAP.value, status="success"
            ).inc()

            logger.info(
                "mcp_get_project_map_success",
                repository_id=repository_id,
                max_depth=max_depth,
                duration=duration,
            )

            return [TextContent(type="text", text=project_map)]

    except Exception as e:
        duration = time.time() - start_time
        mcp_tool_calls_total.labels(
            tool_name=MCPToolEnum.GET_PROJECT_MAP.value, status="error"
        ).inc()
        logger.error(
            "mcp_get_project_map_failed",
            repository_id=repository_id,
            max_depth=max_depth,
            error=str(e),
            error_type=type(e).__name__,
            duration=duration,
            exc_info=True,
        )
        return [
            TextContent(
                type="text",
                text=f"\u274c Failed to generate project map: {str(e)}\n\n"
                f"Error type: {type(e).__name__}\n\n"
                f"\ud83d\udca1 Tips:\n"
                f"- Verify the repository ID is correct using `list_repositories()`\n"
                f"- Check that the repository has been successfully synced\n"
                f"- Try with a smaller max_depth value (e.g., 1 or 2)",
            )
        ]


async def get_module_metadata(
    repository_id: int,
    module_path: str,
    generate_if_missing: bool = True
) -> List[TextContent]:
    """
    Get structured metadata and symbols for a specific module (No LLM).

    Args:
        repository_id: Repository ID
        module_path: Path to module (e.g., "src/api", "backend/auth")
        generate_if_missing: Ignored

    Returns:
        Module metadata with AST basics and docstrings as JSON
    """
    import json
    from src.utils.module_identifier import ModuleIdentifier
    
    if repository_id is None:
        return [
            TextContent(
                type="text",
                text="❌ Missing required parameter: repository_id"
            )
        ]
    if not module_path:
        return [
            TextContent(
                type="text",
                text="❌ Missing required parameter: module_path"
            )
        ]
    
    start_time = time.time()
    try:
        async with get_async_session() as session:
            identifier = ModuleIdentifier(session)
            modules = await identifier.identify_modules(repository_id, 0, 10)
            module_info = next((m for m in modules if m.path == module_path), None)

            if not module_info:
                return [
                    TextContent(
                        type="text",
                        text=f"❌ Module '{module_path}' not found in repository {repository_id}."
                    )
                ]

            symbols = await identifier.get_module_symbols(repository_id, module_path, limit=50)

            metadata = {
                "module_name": module_info.name,
                "path": module_info.path,
                "type": module_info.module_type,
                "is_package": module_info.is_package,
                "file_count": module_info.file_count,
                "symbol_count": module_info.symbol_count,
                "line_count": module_info.line_count,
                "languages": module_info.languages,
                "entry_points": module_info.entry_points,
                "files": module_info.files,
                "symbols": symbols
            }

            duration = time.time() - start_time
            mcp_tool_duration.labels(tool_name=MCPToolEnum.GET_MODULE_METADATA.value).observe(duration)
            mcp_tool_calls_total.labels(tool_name=MCPToolEnum.GET_MODULE_METADATA.value, status="success").inc()

            return [TextContent(type="text", text=json.dumps(metadata, indent=2))]

    except Exception as e:
        duration = time.time() - start_time
        mcp_tool_calls_total.labels(tool_name=MCPToolEnum.GET_MODULE_METADATA.value, status="error").inc()
        logger.error(f"Failed to get module metadata: {e}", exc_info=True)
        return [TextContent(type="text", text=f"Failed to get module metadata: {str(e)}")]


async def query_codebase_structure(
    query: str,
    repository_id: Optional[int] = None,
    limit: int = 50
) -> List[TextContent]:
    """
    Query codebase structure using natural language (Phase 4: Text-to-SQL).
    
    Translates natural language queries into SQL queries against the codebase schema.
    Disabled for security reasons (Zero Egress architecture).
    """
    return [
        TextContent(
            type="text",
            text="❌ The query_codebase_structure (Text-to-SQL) tool has been disabled for security reasons."
        )
    ]
