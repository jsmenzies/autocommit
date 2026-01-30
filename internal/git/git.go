package git

import (
	"bytes"
	"fmt"
	"os/exec"
	"strings"
)

func IsGitRepo() bool {
	cmd := exec.Command("git", "rev-parse", "--git-dir")
	err := cmd.Run()
	return err == nil
}

func HasStagedChanges() bool {
	cmd := exec.Command("git", "diff", "--cached", "--quiet")
	err := cmd.Run()
	return err != nil
}

func GetCurrentBranch() (string, error) {
	cmd := exec.Command("git", "branch", "--show-current")
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to get current branch: %w", err)
	}
	return strings.TrimSpace(string(output)), nil
}

func GetStagedDiff() (string, error) {
	if !HasStagedChanges() {
		return "", fmt.Errorf("no staged changes found")
	}

	cmd := exec.Command("git", "diff", "--cached")
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to get staged diff: %w", err)
	}

	return string(output), nil
}

type CommitInfo struct {
	Hash    string
	Message string
	Author  string
	Date    string
}

func GetRecentCommits(n int) ([]CommitInfo, error) {
	if n <= 0 {
		n = 5
	}

	format := "%H|%s|%an|%ad"
	cmd := exec.Command("git", "log", "-n", fmt.Sprintf("%d", n), fmt.Sprintf("--format=%s", format))
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to get recent commits: %w", err)
	}

	var commits []CommitInfo
	lines := bytes.Split(output, []byte("\n"))
	for _, line := range lines {
		if len(line) == 0 {
			continue
		}

		parts := bytes.SplitN(line, []byte("|"), 4)
		if len(parts) < 4 {
			continue
		}

		commits = append(commits, CommitInfo{
			Hash:    string(parts[0]),
			Message: string(parts[1]),
			Author:  string(parts[2]),
			Date:    string(parts[3]),
		})
	}

	return commits, nil
}

func GetRecentCommitMessages(n int) ([]string, error) {
	commits, err := GetRecentCommits(n)
	if err != nil {
		return nil, err
	}

	var messages []string
	for _, commit := range commits {
		messages = append(messages, commit.Message)
	}

	return messages, nil
}

func DoCommit(message string) error {
	cmd := exec.Command("git", "commit", "-m", message)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to commit: %w\nOutput: %s", err, string(output))
	}
	return nil
}

// AddAll stages all changes in the repository (modified, deleted, and untracked files)
func AddAll() error {
	// Use -A to add all changes including deletions, modifications, and untracked files
	cmd := exec.Command("git", "add", "-A")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to add files: %w\nOutput: %s", err, string(output))
	}
	return nil
}

func CommitWithOptions(message string, amend bool, noVerify bool) error {
	args := []string{"commit", "-m", message}

	if amend {
		args = append(args, "--amend")
	}

	if noVerify {
		args = append(args, "--no-verify")
	}

	cmd := exec.Command("git", args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to commit: %w\nOutput: %s", err, string(output))
	}
	return nil
}

// Push pushes the current branch to its upstream remote
func Push() error {
	cmd := exec.Command("git", "push")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to push: %w\nOutput: %s", err, string(output))
	}
	return nil
}
