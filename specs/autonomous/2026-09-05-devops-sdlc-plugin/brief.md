---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: ["CLAUDE.md"]
date: 2026-09-05
author: BMAD analyst / authorized autonomous surrogate
workflow: create-brief
---

# Product Brief: DevOps SDLC Plugin

## Executive Summary

Build an installable Claude Code plugin that carries existing Terraform, Terraspace, and Python/Pulumi repositories from issue through a reviewed draft pull request. It reuses the established PHP/React SDLC stages while adding infrastructure identity, state, secret, and plan controls. The user aims to automate at least 90% of eligible routine DevOps work; acceptance distinguishes workflow coverage from empirically measured time savings.

## Core Vision

### Problem Statement

Existing infrastructure changes require repeated repository discovery, tool selection, planning, review, testing, CI repair, and comment reconciliation. Language-specific SDLC plugins do not model infrastructure targets, cloud identity, sensitive previews, or state operations.

### Problem Impact

Manual coordination increases repetitive effort and makes incomplete evidence easy to confuse with successful infrastructure validation. Incorrect workspace or stack selection can affect resources beyond the requested change.

### Why Existing Solutions Fall Short

The existing PHP/React plugins provide proven staged orchestration but assume language-specific profiles. IaC CLIs provide validation and preview without an integrated issue-to-PR workflow or independent FR/NFR review.

### Proposed Solution

Ship eight do-sdlc commands, focused agents and reusable skills, a validated repository profile, and a Python standard-library helper. Automate safe local checks and explicit previews, preserve immutable evidence, and stop at scope-bound authorization boundaries for cloud mutation.

### Key Differentiators

Repository-derived commands and multiple IaC targets replace hardcoded project assumptions. Independent review, honest blocked/skipped statuses, bounded loops, and draft-only PR completion make evidence reviewable.

## Target Users

### Primary Users

The repository maintainer owns Terraform/Terraspace and Python/Pulumi infrastructure and wants routine change preparation delegated without surrendering deployment control. They currently coordinate tool invocation, review, and CI manually. Success is a reproducible, reviewable draft PR with accurate evidence and only material decisions escalated.

### Secondary Users

Infrastructure reviewers need target identity, state impact, security findings, and rollback considerations. Developers consuming infrastructure need documented compatibility and service behavior. Operators retain cloud mutation and emergency decisions.

### User Journey

Install the plugin; discover repository targets; review the generated profile; submit an issue; generate BMAD artifacts; implement a bounded change; independently review and exercise it; repair CI and review findings; receive a draft PR with evidence. Later invocations resume from persisted artifacts and recheck current conditions.

## Success Metrics

At release, at least 90% of the explicitly declared eligible routine-work categories have a implemented workflow and reproducible acceptance evidence. Report supported-category coverage separately from autonomous successful executions and human minutes saved. Exclude only justified tasks requiring owner decisions, emergency judgment, cloud mutation approval, or unavailable integrations; list excluded and blocked cases openly.

### Business Objectives

Reduce repetitive engineering effort while preserving deployment control and improving review evidence. No revenue or adoption target was supplied.

### Key Performance Indicators

- Eligible-category workflow coverage: supported categories divided by declared eligible categories; target at least 90%.
- Operational automation rate: accepted runs completed without unplanned intervention divided by eligible observed runs; target at least 90%, pending real usage evidence.
- Human-time reduction: comparable baseline versus assisted hands-on minutes; target at least 90%, unproven until measured.
- Release integrity: all required deterministic checks pass; live/manual/judge checks state executed, blocked, failed, or skipped accurately; zero unresolved review blockers for final draft PR.
- Safety corpus: zero unauthorized mutation and zero secret disclosures in positive, negative, edge, and adversarial cases.

## MVP Scope

### Core Features

Installable marketplace packaging; eight staged commands; target profile discovery and strict validation; Terraform/Terraspace/Pulumi execution routing; BMAD/BMALPH orchestration; independent implementation, security/state, requirements, QA, CI, and comment agents; reusable IaC skills; immutable evidence; unit, integration, adversarial, manual E2E, and LLM judge validation.

### Out of Scope for MVP

Cloud apply/destroy execution in the helper, automatic state repair/import/migration, production deployment without scope-bound reviewed authorization, hosted services, new infrastructure platforms, merging or releasing the resulting PR, and a claim to enumerate every possible DevOps case.

### MVP Success Criteria

A validated installable plugin, reproducible positive/negative/edge corpus, honest manual and live-model evidence, and a draft PR with current required checks green and review findings addressed. Absent credentials or unavailable external checks remain visible release evidence gaps.

### Future Vision

Measure real task frequency and hands-on time, expand supported adapters based on observed demand, and introduce separately reviewed deployment integrations when authorization contracts and recovery evidence are available.
