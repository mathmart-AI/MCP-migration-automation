package resources

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"

	copilot "github.com/github/copilot-sdk/go"
)

type ReadDirParams struct {
	SubDir string `json:"subDir" jsonschema:"The sub-directory to read (e.g. 'docs', 'helm-platform', 'diffs')"`
}

type ReadFileParams struct {
	FilePath string `json:"filePath" jsonschema:"The relative path to the file to read, e.g. 'docs/migration.md'"`
}

func ExposeResources(contextDir string) []copilot.Tool {
	return []copilot.Tool{
		copilot.DefineTool(
			"list_directory_contents",
			"Lists all files inside a specific directory (like docs, helm-platform, diffs) within the context.",
			func(params ReadDirParams, inv copilot.ToolInvocation) (any, error) {
				targetDir := filepath.Join(contextDir, params.SubDir)

				// Validate that it doesn't escape context dir
				if !filepath.HasPrefix(filepath.Clean(targetDir), filepath.Clean(contextDir)) {
					return nil, fmt.Errorf("access denied")
				}

				var files []string
				err := filepath.WalkDir(targetDir, func(path string, d fs.DirEntry, err error) error {
					if err != nil {
						return nil // skip errors
					}
					if !d.IsDir() {
						rel, _ := filepath.Rel(contextDir, path)
						files = append(files, rel)
					}
					return nil
				})

				if err != nil {
					return nil, err
				}

				return files, nil
			},
		),
		copilot.DefineTool(
			"read_file_content",
			"Reads the text content of a file within the context. Use this to read documentation, helm templates, or diffs.",
			func(params ReadFileParams, inv copilot.ToolInvocation) (any, error) {
				targetFile := filepath.Join(contextDir, params.FilePath)

				if !filepath.HasPrefix(filepath.Clean(targetFile), filepath.Clean(contextDir)) {
					return nil, fmt.Errorf("access denied")
				}

				content, err := os.ReadFile(targetFile)
				if err != nil {
					return nil, err
				}

				return string(content), nil
			},
		),
	}
}
