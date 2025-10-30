<!--
SYNC IMPACT REPORT
==================
Version Change: 1.0.0 → 1.1.0
Reason: MINOR bump - Added pre-commit requirement to Development Workflow (material expansion of requirements)

Modified Principles:
  - Development Workflow > Pull Request Process: Added mandatory pre-commit validation requirement

Added Sections: N/A

Removed Sections: N/A

Templates Requiring Updates:
  ✅ plan-template.md - No changes needed (Constitution Check section remains valid)
  ✅ spec-template.md - No changes needed (requirements structure compatible)
  ✅ tasks-template.md - No changes needed (task categorization supports pre-commit)
  ✅ Commands in .claude/commands/ - No changes needed

Follow-up TODOs: None
-->

# nf-core/cellpainting Constitution

## Core Principles

### I. Template Compliance (NON-NEGOTIABLE)

All pipeline development MUST adhere to the official nf-core template structure and requirements.

**Rules:**

- Pipeline MUST be built from and maintain sync with the nf-core template (current: v3.3.2)
- All updates from `nf-core/tools` template MUST be regularly synchronized
- Template branch `TEMPLATE` MUST be maintained for automated sync capability
- MUST pass all `nf-core pipelines lint` validation tests before any release
- Custom deviations from template MUST be documented in `.nf-core.yml` with explicit justification

**Rationale:** Template compliance ensures consistency across the nf-core ecosystem, enables community maintainability, and guarantees adherence to evolving best practices. The template embodies accumulated community wisdom and prevents technical debt.

### II. Modular Design (NON-NEGOTIABLE)

Workflows MUST be composed of reusable, single-purpose modules and subworkflows following DSL2 architecture.

**Rules:**

- Each process MUST be defined as a standalone module with clear inputs/outputs
- Prefer nf-core/modules over local modules when functionality exists
- Local modules MUST follow nf-core module structure: `modules/local/<tool>/main.nf`
- Modules MUST be independently testable with nf-test
- Subworkflows MUST coordinate related processes with explicit `take`/`emit` blocks
- NO monolithic process definitions or tight coupling between unrelated processes

**Rationale:** Modularity enables code reuse, simplified testing, parallel development, and community contribution. Single-purpose modules are easier to debug, maintain, and compose into new workflows.

### III. Testing Discipline (NON-NEGOTIABLE)

All code changes MUST include nf-test validation with appropriate test data.

**Rules:**

- Every module MUST have nf-test unit tests validating core functionality
- Every subworkflow MUST have nf-test integration tests
- Main workflow MUST have end-to-end pipeline tests with `-profile test`
- Test data MUST use minimal representative datasets (NOT full production data)
- Tests MUST execute in CI/CD before any merge to `dev` or `master`
- Tests MUST verify expected outputs, not just successful execution
- NO untested code merged to protected branches

**Rationale:** Comprehensive testing prevents regressions, enables confident refactoring, and ensures pipeline reliability across diverse execution environments. Test-first development catches integration issues early.

### IV. nf-core Standards (NON-NEGOTIABLE)

Pipeline development MUST comply with all mandatory nf-core guidelines.

**Rules:**

- MUST use semantic versioning (MAJOR.MINOR.PATCH) for all releases
- MUST support Docker/Singularity/Conda execution via `-profile` configuration
- MUST use standardized parameter naming conventions across nf-core pipelines
- MUST include comprehensive documentation on nf-co.re website
- MUST maintain git branching model: `master` (stable), `dev` (development), `TEMPLATE` (sync)
- MUST provide `--help` output documenting all parameters
- MUST use MIT open-source license
- MUST acknowledge community contributions and prior work
- NO pipeline-specific conventions that conflict with nf-core standards

**Rationale:** Standardization enables users to transition seamlessly between nf-core pipelines, reduces learning curve, and maintains ecosystem coherence. Consistent interfaces improve usability and community adoption.

### V. Container Reproducibility (NON-NEGOTIABLE)

All software dependencies MUST be packaged in versioned containers with explicit version pinning.

**Rules:**

- Every process MUST specify container directive with exact version tag
- Containers MUST be pulled from Biocontainers, Docker Hub, or Seqera Wave
- MUST support Docker, Singularity, and Conda execution environments
- NO `latest` tags - all containers MUST use explicit semantic versions
- Container definitions MUST be tested in CI/CD across execution platforms
- Software version reporting MUST be collected via `versions.yml` in each module

**Rationale:** Version pinning ensures reproducibility across time and execution environments. Explicit versioning prevents "works on my machine" issues and enables audit trails for scientific reproducibility.

### VI. Documentation Excellence

All pipeline features MUST include clear, comprehensive documentation for users and developers.

**Rules:**

- README MUST include quick start, installation, and basic usage examples
- Every parameter MUST be documented in `nextflow_schema.json` with description and type
- Usage documentation MUST provide samplesheet format with examples
- Output documentation MUST describe all published results and their scientific meaning
- Module-level documentation MUST explain tool purpose, parameters, and outputs
- MUST maintain CHANGELOG.md documenting all notable changes per release
- Complex workflows MUST include visual diagrams showing dataflow

**Rationale:** Documentation is the primary interface for users and future maintainers. Well-documented pipelines reduce support burden, enable self-service adoption, and ensure scientific correctness through transparent methodology.

### VII. Channel-Driven Dataflow

Workflow logic MUST use Nextflow channels for reactive, push-based dataflow orchestration.

**Rules:**

- Data MUST flow through channels, not shared state or global variables
- Channel operations (map, filter, join, groupTuple) MUST handle metadata propagation
- Metadata MUST travel with data throughout the workflow via tuple channels
- Process inputs/outputs MUST use typed channel declarations (`tuple`, `path`, `val`)
- Complex metadata operations MUST be tested for correctness (e.g., grouping by batch/plate)
- NO imperative loops or procedural control flow for data processing

**Rationale:** Channel-driven design leverages Nextflow's parallelization engine, enables implicit data parallelism, and creates maintainable workflows. Proper metadata handling prevents sample mix-ups and enables provenance tracking.

## Development Workflow

### Pull Request Process

**Requirements:**

- All changes MUST be developed on feature branches following pattern: `<issue-number>-<feature-name>`
- PRs MUST target `dev` branch (NOT `master` directly)
- PR title MUST follow conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`
- PR description MUST reference related issues and explain the change rationale
- MUST include tests demonstrating functionality and preventing regressions
- MUST update relevant documentation (README, usage docs, parameter docs)
- MUST pass all CI/CD checks (linting, tests, Docker builds) before merge

### Pre-Commit Validation (NON-NEGOTIABLE)

All commits MUST pass pre-commit hooks before being committed to version control.

**Requirements:**

- MUST run `pre-commit run` (or `pre-commit run --all-files` for comprehensive check) before every commit
- Pre-commit hooks MUST pass without errors before git commit is allowed
- Hooks enforce: code formatting (Prettier), trailing whitespace removal, end-of-file fixes
- If hooks modify files automatically, stage those changes and commit again
- NEVER bypass pre-commit with `--no-verify` unless explicitly approved by maintainer for emergency fixes

**Rationale:** Pre-commit hooks catch formatting and style issues immediately, preventing linting failures in CI/CD and reducing code review friction. Automated enforcement ensures consistent code quality across all contributors without manual oversight.

### Code Review Standards

**Requirements:**

- All PRs MUST receive approval from at least one maintainer before merge
- Reviewers MUST verify constitution compliance, especially testing and documentation
- Reviewers MUST validate scientific correctness of bioinformatics logic
- Feedback MUST be addressed with code changes or explicit justification
- Complex changes (>500 lines) SHOULD be broken into smaller reviewable PRs

### CI/CD Quality Gates

**Requirements:**

- GitHub Actions MUST run on every PR and push to `dev`/`master`
- Linting workflow MUST pass (prettier, EditorConfig, nf-core lint)
- nf-test workflow MUST pass all tests across execution profiles
- Full-size tests MUST pass before release (via `-profile test_full` if available)
- Docker containers MUST build successfully in CI

## Quality Assurance

### Testing Requirements

**Mandatory Tests:**

- **Unit Tests**: Every module in `modules/local/` MUST have nf-test with `tests/` directory
- **Integration Tests**: Subworkflows MUST validate multi-module coordination
- **End-to-End Tests**: Main workflow MUST have `-profile test` with minimal data
- **Regression Tests**: Bug fixes MUST include tests preventing recurrence

**Test Data Management:**

- Test data MUST be minimal (KB to MB, not GB)
- Test data SHOULD be hosted in nf-core/test-datasets repository
- Local test data MUST be documented in `tests/` with clear provenance

### Linting Compliance

**Requirements:**

- MUST pass `nf-core pipelines lint` with no errors (warnings acceptable with justification)
- Code formatting MUST use Prettier with project `.prettierrc.yml` configuration
- EditorConfig settings MUST be respected (indentation, line endings)
- Nextflow DSL2 syntax MUST follow nf-core style guide
- Custom lint exceptions MUST be documented in `.nf-core.yml` under `lint:` section

## Governance

### Amendment Procedure

This constitution may be amended through the following process:

1. **Proposal**: Create GitHub issue documenting proposed change with rationale
2. **Discussion**: Gather feedback from maintainers and community via issue/Slack
3. **Documentation**: Update `.specify/memory/constitution.md` with changes
4. **Version Bump**: Increment constitution version following semantic versioning:
   - **MAJOR**: Removing principles or backward-incompatible governance changes
   - **MINOR**: Adding new principles or materially expanding requirements
   - **PATCH**: Clarifications, wording improvements, non-semantic refinements
5. **Propagation**: Update dependent templates (`plan-template.md`, `spec-template.md`, `tasks-template.md`)
6. **Approval**: Obtain maintainer consensus before finalizing
7. **Migration Plan**: If amendment impacts existing code, document migration path

### Compliance Review

**Responsibilities:**

- ALL pull requests MUST verify compliance with this constitution
- Maintainers MUST flag constitution violations during code review
- Quarterly reviews SHOULD assess adherence and identify improvement areas
- Constitution updates MUST be communicated to all contributors via Slack/GitHub

### Complexity Justification

When violating simplicity principles is necessary:

1. Document the specific problem being solved
2. Explain why simpler alternatives are insufficient
3. Include justification in PR description and inline code comments
4. Obtain explicit maintainer approval for architectural complexity

### Living Document

This constitution is a living document reflecting current best practices. As the nf-core ecosystem evolves, this constitution MUST be updated to reflect new standards, tools, and community consensus.

**Version**: 1.1.0 | **Ratified**: 2025-10-30 | **Last Amended**: 2025-10-30
