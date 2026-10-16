# ADR 0001: Record Architecture Decisions

* Status: accepted
* Date: 2026-10-16
* Deciders: Lead Developer, Antigravity Agent

## Context and Problem Statement

As this iOS codebase evolves across paired developer and autonomous AI agent sessions, architectural decisions and technical constraints risk being forgotten, re-debated, or violated in future sessions.

## Decision Drivers

* Institutional memory persistence across agent contexts.
* Clear rationale for non-obvious engineering decisions.
* Prevention of regression loops.

## Considered Options

* Markdown files in `docs/adr/` using MADR format.
* Ad-hoc comments in source code.
* Git commit messages only.

## Decision Outcome

Chosen option: Markdown files in `docs/adr/` using the MADR template, because it is self-contained in the repository, version-controlled with git, and readable by both humans and LLM agents.
