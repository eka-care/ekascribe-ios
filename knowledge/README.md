# Knowledge Base

This directory contains documentation and knowledge management for the EkaScribeSDK project. It serves as the central repository for project history, architectural decisions, and learnings.

---

## Files in this Directory

### 📖 [PROJECT_HISTORY.md](./PROJECT_HISTORY.md) (Public - Version Controlled)
**Purpose**: Documents the evolution of the SDK over time

**Contents**:
- Project iterations and major milestones
- Architectural Decision Records (ADRs)
- Component evolution and capabilities
- Breaking changes log
- Performance optimization history
- Future roadmap

**When to Update**:
- After completing significant features or iterations
- When making architectural decisions
- After breaking changes or major refactoring
- When discovering production issues and their fixes
- During performance optimization work

**Audience**: All team members, contributors, and maintainers

---

### 📝 LESSONS.md (Private - Not Version Controlled)
**Purpose**: Personal knowledge base for development learnings

**Contents**:
- Mistakes made and how they were fixed
- Anti-patterns to avoid
- Best practices discovered
- Component-specific insights
- Debugging tips and non-obvious solutions
- Testing strategies

**When to Update**:
- After encountering and fixing a bug
- When discovering an anti-pattern
- After solving a difficult problem
- When finding an effective pattern or approach
- Before starting new work (review first to avoid past mistakes)

**Audience**: Individual developers (private notes)

**Note**: This file is excluded from version control via `.gitignore`

---

## Purpose of the Knowledge Base

### 1. Institutional Knowledge
Preserve context and rationale for decisions made during development. Future team members can understand *why* things are built a certain way, not just *what* was built.

### 2. Prevent Repeated Mistakes
Document problems encountered and their solutions so the same issues don't occur multiple times.

### 3. Accelerate Onboarding
New contributors can read through `PROJECT_HISTORY.md` to quickly understand the project's evolution and current state.

### 4. Support Decision Making
When facing similar decisions, review past Architecture Decision Records (ADRs) to maintain consistency.

### 5. Track Technical Debt
Document known issues and planned improvements in one place.

---

## How to Use This Knowledge Base

### For New Team Members
1. **Start with**: `PROJECT_HISTORY.md` - Understand the project's evolution
2. **Review**: Architecture Decision Records (ADRs) section
3. **Understand**: Component architecture and responsibilities
4. **Check**: Future roadmap for planned work

### For Daily Development
1. **Before starting work**: Review `LESSONS.md` for relevant past learnings
2. **When making decisions**: Check if similar decisions were made before (ADRs)
3. **After completing work**: Update `PROJECT_HISTORY.md` if significant
4. **After fixing bugs**: Document in `LESSONS.md` to prevent recurrence

### For Planning New Features
1. **Review**: Past iterations to understand development patterns
2. **Check**: Component evolution to see what's already built
3. **Consider**: Technical debt that could be addressed
4. **Document**: New ADRs for significant architectural decisions

### For Troubleshooting
1. **Check**: `LESSONS.md` for similar issues encountered before
2. **Review**: Component-specific notes for known gotchas
3. **Consult**: Debugging insights section
4. **Document**: New solutions discovered

---

## Update Guidelines

### What to Document in PROJECT_HISTORY.md ✅
- New iterations or releases
- Architectural decisions (using ADR format)
- Breaking changes with migration paths
- Performance optimizations with measured impact
- Production issues and their resolutions
- Component capability changes
- Dependency updates with rationale

### What to Document in LESSONS.md ✅
- Bugs encountered and fixed
- Anti-patterns discovered
- Effective testing strategies
- Component-specific gotchas
- Non-obvious debugging solutions
- Platform-specific issues

### What NOT to Document ❌
- Routine code changes without architectural impact
- Temporary workarounds (fix properly instead)
- Incomplete information or speculation
- Sensitive data or credentials
- Implementation details better suited for code comments

---

## Document Templates

### Architecture Decision Record (ADR) Template
Use this format in `PROJECT_HISTORY.md`:

```markdown
### ADR-XXX: [Decision Title]
**Status**: [Proposed | Accepted | Deprecated | Superseded]
**Date**: [Date]
**Context**: [What is the situation forcing a decision?]
**Decision**: [What is the decision being made?]
**Consequences**:
- ✅ [Positive consequence]
- ❌ [Negative consequence or trade-off]
**Alternatives Considered**: [Other options and why they were rejected]
```

### Iteration Log Template
Use this format in `PROJECT_HISTORY.md`:

```markdown
### Iteration X: [Iteration Name]
**Date**: [Start date - End date]
**Commits**: [Relevant commit hashes]

**What Was Built**:
- [Feature or component 1]
- [Feature or component 2]

**Key Decisions**:
- [Decision 1 and rationale]
- [Decision 2 and rationale]

**Challenges Encountered**:
- [Challenge] → [How it was resolved]

**Metrics/Impact**:
- [Measurable outcome if applicable]
```

### Lesson Learned Template
Use this format in `LESSONS.md`:

```markdown
### [Date] - [Brief Description]
**What Happened**: [Describe the issue]
**Root Cause**: [Why it happened]
**How Fixed**: [Solution that worked]
**Prevention**: [How to avoid in the future]
**Related Files**: [Files or components affected]
```

---

## Integration with Development Workflow

The knowledge base integrates with the standard development workflow defined in `CLAUDE.md`:

```
Plan → User Approval → Execute → Build Verification → Test Execution → Update Knowledge Base → User Handover
```

**During Planning**:
- Review `LESSONS.md` for similar past work
- Check `PROJECT_HISTORY.md` for architectural patterns
- Consider existing ADRs for consistency

**During Execution**:
- Note any surprising discoveries or issues for later documentation
- Track decisions made for potential ADR creation

**After Verification**:
- Update `LESSONS.md` with any mistakes and fixes
- Update `PROJECT_HISTORY.md` for significant changes
- Document new patterns or anti-patterns

**Before Handover**:
- Ensure knowledge base is current
- Link to relevant documentation in handover notes

---

## Best Practices

### Writing Style
- **Be concise** - Get to the point quickly
- **Be specific** - Include file paths, dates, and concrete examples
- **Be honest** - Document mistakes and failures, not just successes
- **Be actionable** - Provide clear steps or recommendations
- **Use examples** - Code snippets or scenarios clarify abstract concepts

### Organization
- Keep sections focused and single-purpose
- Use consistent formatting and templates
- Link related information across documents
- Archive old content periodically (every 6 months)
- Use clear headings for easy navigation

### Maintenance
- Review and update quarterly
- Remove outdated or incorrect information
- Consolidate duplicate entries
- Ensure links and references are current
- Archive completed roadmap items

---

## Related Documentation

- **CLAUDE.md**: Development workflow and coding standards (private, not version controlled)
- **plan/plan.md**: Current implementation plan (private, not version controlled)
- **plan/tasks.md**: Current task tracking (private, not version controlled)
- **README.md** (root): User-facing SDK documentation
- **Package.swift**: Package configuration and dependencies

---

## Questions or Suggestions?

If you have questions about what to document or suggestions for improving the knowledge base structure, discuss with the team or open an issue.

**Remember**: Good documentation is an investment in the future of the project. Take time to document learnings while they're fresh!

---

*This knowledge base is a living document. Keep it current, relevant, and useful.*

**Last Updated**: March 16, 2026
