package main

import (
	"context"
	"dagger/runestone/internal/dagger"
)

// Runestone is the main module for the Runestone Elixir project
type Runestone struct{}

// Test runs mix test on the Elixir project
func (m *Runestone) Test(ctx context.Context, source *dagger.Directory) (string, error) {
	return dag.Container().
		From("elixir:1.16-alpine").
		WithDirectory("/app", source).
		WithWorkdir("/app").
		WithExec([]string{"mix", "local.hex", "--force"}).
		WithExec([]string{"mix", "local.rebar", "--force"}).
		WithExec([]string{"mix", "deps.get"}).
		WithExec([]string{"mix", "test"}).
		Stdout(ctx)
}

// Format checks code formatting with mix format
func (m *Runestone) Format(ctx context.Context, source *dagger.Directory) (string, error) {
	return dag.Container().
		From("elixir:1.16-alpine").
		WithDirectory("/app", source).
		WithWorkdir("/app").
		WithExec([]string{"mix", "format", "--check-formatted"}).
		Stdout(ctx)
}

// Compile compiles the Elixir project
func (m *Runestone) Compile(ctx context.Context, source *dagger.Directory) (string, error) {
	return dag.Container().
		From("elixir:1.16-alpine").
		WithDirectory("/app", source).
		WithWorkdir("/app").
		WithExec([]string{"mix", "local.hex", "--force"}).
		WithExec([]string{"mix", "local.rebar", "--force"}).
		WithExec([]string{"mix", "deps.get"}).
		WithExec([]string{"mix", "compile"}).
		Stdout(ctx)
}

// Server starts the Phoenix server (if applicable)
func (m *Runestone) Server(ctx context.Context, source *dagger.Directory) *dagger.Service {
	return dag.Container().
		From("elixir:1.16-alpine").
		WithDirectory("/app", source).
		WithWorkdir("/app").
		WithExec([]string{"mix", "local.hex", "--force"}).
		WithExec([]string{"mix", "local.rebar", "--force"}).
		WithExec([]string{"mix", "deps.get"}).
		WithExec([]string{"mix", "compile"}).
		WithExposedPort(4000).
		AsService()
}

// Deps gets and compiles dependencies
func (m *Runestone) Deps(ctx context.Context, source *dagger.Directory) (string, error) {
	return dag.Container().
		From("elixir:1.16-alpine").
		WithDirectory("/app", source).
		WithWorkdir("/app").
		WithExec([]string{"mix", "local.hex", "--force"}).
		WithExec([]string{"mix", "local.rebar", "--force"}).
		WithExec([]string{"mix", "deps.get"}).
		WithExec([]string{"mix", "deps.compile"}).
		Stdout(ctx)
}
