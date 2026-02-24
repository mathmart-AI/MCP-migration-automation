package main

import (
	"archive/tar"
	"compress/gzip"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
)

// Default exclusions
var excludeDirs = map[string]bool{
	".git":         true,
	".venv":        true,
	"venv":         true,
	"node_modules": true,
	"bin":          true,
	"obj":          true,
	"__pycache__":  true,
	".gemini":      true,
	".idea":        true,
	".vscode":      true,
}

var excludeFiles = map[string]bool{
	".DS_Store":   true,
	"axon-cli":    true,
	"axon-packer": true,
}

func main() {
	srcPtr := flag.String("src", ".", "Directory to archive")
	outPtr := flag.String("out", "archive.tar.gz", "Output filename")
	flag.Parse()

	srcPath, err := filepath.Abs(*srcPtr)
	if err != nil {
		log.Fatalf("Failed to get absolute path: %v", err)
	}

	fmt.Printf("📦  Packing %s into %s...\n", srcPath, *outPtr)

	// Create output file
	outFile, err := os.Create(*outPtr)
	if err != nil {
		log.Fatalf("Failed to create output file: %v", err)
	}
	defer outFile.Close()

	// Setup gzip and tar
	gw := gzip.NewWriter(outFile)
	defer gw.Close()
	tw := tar.NewWriter(gw)
	defer tw.Close()

	var fileCount int
	var skippedCount int

	err = filepath.Walk(srcPath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		relPath, err := filepath.Rel(srcPath, path)
		if err != nil {
			return err
		}

		// Don't include the source root directory itself as an entry if it's "."
		if relPath == "." {
			return nil
		}

		// Check if the output file is inside the source directory (avoid infinite loop or self-inclusion)
		outAbs, _ := filepath.Abs(*outPtr)
		if path == outAbs {
			return nil
		}

		base := filepath.Base(path)

		// Skip all archive files to avoid recursive bloat
		if strings.HasSuffix(base, ".tar.gz") {
			return nil
		}

		// Exclusion logic
		if info.IsDir() {
			if excludeDirs[base] {
				skippedCount++
				return filepath.SkipDir
			}
		} else {
			if excludeFiles[base] || strings.HasSuffix(base, ".log") || strings.HasSuffix(base, ".tmp") {
				skippedCount++
				return nil
			}
		}

		// Create tar header
		header, err := tar.FileInfoHeader(info, relPath)
		if err != nil {
			return err
		}
		header.Name = relPath

		if err := tw.WriteHeader(header); err != nil {
			return err
		}

		if !info.IsDir() {
			file, err := os.Open(path)
			if err != nil {
				return err
			}
			defer file.Close()
			if _, err := io.Copy(tw, file); err != nil {
				return err
			}
			fileCount++
		}

		return nil
	})

	if err != nil {
		log.Fatalf("Error walking the path: %v", err)
	}

	tw.Close()
	gw.Close()
	outFile.Close()

	info, _ := os.Stat(*outPtr)
	fmt.Printf("\n✨  Done!\n")
	fmt.Printf("   Files added: %d\n", fileCount)
	fmt.Printf("   Items skipped: %d\n", skippedCount)
	fmt.Printf("   Archive size: %.2f MB\n", float64(info.Size())/(1024*1024))
}
