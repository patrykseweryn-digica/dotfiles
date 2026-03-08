# Subagent Prompt Templates

These are the 4 prompts to use with `Task` tool (`subagent_type="Explore"`). Replace `{ROOT}` with the actual codebase root path before launching.

---

## 1. Architecture Scout

```
Analyze the architecture of the codebase at {ROOT}. Be thorough but strategic — sample broadly rather than reading every file.

INVESTIGATE:
1. **Directory structure**: Run `ls` on top-level and key subdirectories to map the layout. Identify src/, lib/, app/, pkg/, internal/, cmd/, etc.
2. **Languages & frameworks**: Glob for package manifests and config files:
   - package.json, tsconfig.json, next.config.*, vite.config.*, angular.json
   - requirements.txt, setup.py, pyproject.toml, Pipfile, setup.cfg
   - go.mod, go.sum
   - Cargo.toml
   - pom.xml, build.gradle, build.gradle.kts
   - Gemfile, *.gemspec
   - composer.json
   - mix.exs
   - *.csproj, *.sln
   Read the ones you find to extract framework names and versions.
3. **Entry points**: Look for main.*, index.*, app.*, server.*, manage.py, cmd/**/main.go, Program.cs, etc. Read the top ~50 lines of each to understand what they bootstrap.
4. **Dependencies**: From the package manifests, list the top ~15 most significant dependencies (skip trivial utilities). Note any particularly heavy or unusual ones.
5. **Build & dev tooling**: Look for Makefile, Dockerfile, docker-compose.yml, .github/workflows/*.yml, Jenkinsfile, .gitlab-ci.yml, justfile, Taskfile.yml, Earthfile. Summarize what CI/CD and build tools are used.
6. **Configuration**: Check for .env.example, config/, settings/, *.config.js, *.config.ts. Note environment variable patterns.
7. **Monorepo signals**: Check for workspaces in package.json, lerna.json, nx.json, turbo.json, or multiple package manifests at different depths.

OUTPUT FORMAT (use exactly this structure):

### Languages
- [language]: [estimated % of codebase or primary/secondary/minor]

### Frameworks & Libraries
- [name] [version] — [purpose]

### Directory Layout
```
[tree-style overview, max 20 lines]
```

### Entry Points
- [file]: [what it bootstraps]

### Key Dependencies (top 15)
| Dependency | Version | Purpose |
|-----------|---------|---------|
| ... | ... | ... |

### Build & Tooling
- Build: [tools]
- CI/CD: [tools]
- Containerization: [yes/no, what]
- Package manager: [npm/yarn/pnpm/pip/cargo/etc]

### Architecture Pattern
[monolith / microservices / monorepo / serverless / hybrid — with brief justification]

### Notable Observations
- [anything surprising or noteworthy about the architecture]
```

---

## 2. Code Quality Auditor

```
Audit code quality in the codebase at {ROOT}. Sample strategically — check representative files across different modules rather than exhaustively reading everything.

INVESTIGATE:
1. **Long functions**: Grep for function/method definitions and check surrounding line counts. Look for functions exceeding ~80 lines. Search patterns:
   - JS/TS: "function ", "=> {", "async function"
   - Python: "def "
   - Go: "func "
   - Java/C#: "public ", "private ", "protected "
   - Rust: "fn "
   Read a few of the longest functions to understand why they're long.

2. **Deep nesting**: Grep for heavily indented code (4+ levels). Search for patterns like repeated indentation characters. Read surrounding context for the worst offenders.

3. **Code duplication signals**: Look for similar function names across files (e.g., multiple "handleSubmit", "parseResponse", "validateInput"). Check if utility/helper directories exist and are used consistently.

4. **Error handling patterns**:
   - JS/TS: Search for empty catch blocks `catch {}`, `catch (e) {}`, catch blocks that only log
   - Python: Search for bare `except:`, `except Exception:` with just `pass`
   - Go: Search for `_ = err`, `if err != nil` patterns (check if errors are swallowed)
   - General: Look for TODO/FIXME in error handling code

5. **Test coverage signals**:
   - Glob for test directories: test/, tests/, __tests__/, *_test.go, *.test.ts, *.spec.ts, *_test.py, spec/
   - Count test files vs source files (rough ratio)
   - Check if test config exists: jest.config.*, pytest.ini, .coveragerc, coverage/, .nycrc
   - Read 1-2 test files to assess test quality (are they meaningful or just smoke tests?)

6. **Type safety**: Check for TypeScript strict mode, Python type hints usage, Go interface patterns, mypy/pyright config.

7. **Linting & formatting**: Look for .eslintrc*, .prettierrc*, .flake8, .pylintrc, rustfmt.toml, .editorconfig, biome.json. Note what's configured.

OUTPUT FORMAT (use exactly this structure):

### Overall Assessment
[1-2 sentence summary: good/moderate/needs-attention, with key reason]

### Long Functions (top 5)
| File | Function | Lines | Why it's long |
|------|----------|-------|---------------|
| ... | ... | ... | ... |

### Nesting Issues
- [file:line]: [description of deep nesting, what causes it]
(list top 3-5 worst offenders)

### Error Handling
- Pattern: [describe dominant error handling approach]
- Issues found:
  - [file]: [description]
(list top 3-5 issues)

### Duplication Signals
- [description of any detected duplication patterns]

### Test Coverage
- Test files found: [count]
- Source files (approx): [count]
- Ratio: ~[X]%
- Test quality: [assessment based on samples read]
- Coverage tooling: [configured/not configured]

### Type Safety
- [language-specific assessment]

### Linting & Formatting
- Tools configured: [list]
- Strictness: [strict/moderate/loose/not configured]

### Top Recommendations
1. [most impactful improvement]
2. [second most impactful]
3. [third most impactful]
```

---

## 3. TODO/FIXME Hunter

```
Find and categorize all TODO, FIXME, HACK, XXX, and WORKAROUND markers in the codebase at {ROOT}.

SEARCH STRATEGY:
1. Grep for each pattern case-insensitively across all source files:
   - "TODO"
   - "FIXME"
   - "HACK"
   - "XXX"
   - "WORKAROUND"
   - "TEMP" or "TEMPORARY" (in comment context)
   - "DEPRECATED" (self-marked deprecations)
   Exclude node_modules/, vendor/, .git/, dist/, build/, __pycache__/, .venv/, target/, bin/, obj/.
   Use output_mode="content" to capture the actual comment text with surrounding context.

2. For each match, read 1-2 lines of context to understand severity and intent.

3. Categorize each item by severity:
   - **Critical**: Security issues, data loss risks, known bugs in production paths, broken functionality
   - **High**: Missing error handling, incomplete implementations on main paths, performance issues noted by devs
   - **Medium**: Missing features, incomplete edge cases, technical debt acknowledged
   - **Low**: Nice-to-haves, cosmetic issues, minor refactoring desires

4. Group findings by module/directory for actionable organization.

OUTPUT FORMAT (use exactly this structure):

### Summary
- Total markers found: [N]
- TODO: [n] | FIXME: [n] | HACK: [n] | XXX: [n] | WORKAROUND: [n] | Other: [n]

### Critical (address immediately)
| File | Line | Type | Comment |
|------|------|------|---------|
| ... | ... | ... | ... |

### High Priority
| File | Line | Type | Comment |
|------|------|------|---------|
| ... | ... | ... | ... |

### Medium Priority
| File | Line | Type | Comment |
|------|------|------|---------|
| ... | ... | ... | ... |

### Low Priority
| File | Line | Type | Comment |
|------|------|------|---------|
| ... | ... | ... | ... |

### By Module
| Module/Directory | Total | Critical | High | Medium | Low |
|-----------------|-------|----------|------|--------|-----|
| ... | ... | ... | ... | ... | ... |

### Patterns & Observations
- [any patterns: e.g. "most TODOs cluster in auth module", "FIXMEs date back to 2022", "several HACKs around the same API limitation"]

### Staleness Check
- [note any TODOs that reference completed features, outdated APIs, or resolved issues — these are cleanup candidates]
```

---

## 4. Security Surface Scanner

```
Scan for security surface area and common vulnerability patterns in the codebase at {ROOT}. This is a defensive audit, not exploitation — flag risks for developer review.

INVESTIGATE:
1. **Hardcoded secrets**: Grep for patterns suggesting secrets in source code:
   - "password", "passwd", "secret", "api_key", "apikey", "api-key", "token", "auth"
   - "-----BEGIN", "PRIVATE KEY"
   - Base64-encoded strings that look like keys (long alphanumeric strings assigned to variables)
   - Connection strings with embedded credentials
   Exclude: test fixtures, example configs, documentation, .env.example, node_modules/, vendor/.
   Check if .gitignore properly excludes .env, *.pem, *.key files.

2. **Injection risks**:
   - SQL: Search for string concatenation in queries, f-strings/template literals near SQL keywords (SELECT, INSERT, UPDATE, DELETE, WHERE)
   - Command injection: Search for os.system(), subprocess with shell=True, exec(), eval(), child_process.exec()
   - XSS: Search for dangerouslySetInnerHTML, innerHTML assignments, v-html, [innerHTML], {!! !!}
   - Path traversal: Search for user input used in file paths without sanitization

3. **Input validation**:
   - Check API route handlers for input validation (look for validation libraries, schema validation, manual checks)
   - Check form handlers for server-side validation
   - Look for request body parsing without size limits

4. **Authentication & authorization**:
   - Look for auth middleware: search for "auth", "jwt", "session", "passport", "guard", "middleware"
   - Check if routes have auth protection (look for unprotected routes that should be protected)
   - Search for role-based access patterns
   - Look for password hashing: bcrypt, argon2, scrypt, pbkdf2 (flag if using MD5/SHA1 for passwords)

5. **Exposed endpoints & CORS**:
   - Search for CORS configuration: "cors", "Access-Control-Allow-Origin"
   - Look for wildcard origins ("*") in CORS settings
   - Check for debug/admin endpoints that might be exposed
   - Look for API documentation endpoints (swagger, openapi) in production configs

6. **Dependency security signals**:
   - Check for lockfile existence (package-lock.json, yarn.lock, poetry.lock, Cargo.lock, go.sum)
   - Look for .snyk, .npmrc (audit settings), dependabot.yml, renovate.json
   - Note if dependencies appear very outdated based on versions seen

7. **Cryptography**:
   - Search for crypto usage: check for weak algorithms (MD5, SHA1 for security, DES, RC4)
   - Look for random number generation: Math.random(), random.random() used for security purposes (should use crypto-grade)

OUTPUT FORMAT (use exactly this structure):

### Risk Summary
| Category | Findings | Severity |
|----------|----------|----------|
| Hardcoded Secrets | [n] | [highest severity found] |
| Injection Risks | [n] | ... |
| Input Validation | [n] gaps | ... |
| Auth Gaps | [n] | ... |
| CORS/Exposure | [n] | ... |
| Weak Crypto | [n] | ... |

### Hardcoded Secrets
| File | Line | Finding | Severity |
|------|------|---------|----------|
| ... | ... | ... | ... |
(or "None found" + note on .gitignore coverage)

### Injection Risks
| File | Line | Type | Description |
|------|------|------|-------------|
| ... | ... | ... | ... |

### Input Validation Gaps
- [endpoint/handler]: [what validation is missing]

### Authentication & Authorization
- Auth mechanism: [describe what's used]
- Issues:
  - [file]: [description]

### CORS & Exposure
- CORS policy: [describe]
- Exposed debug/admin endpoints: [list or "none found"]

### Dependency Security
- Lockfile: [present/missing]
- Automated scanning: [dependabot/snyk/renovate/none]
- Notable concerns: [any very outdated or known-vulnerable versions]

### Weak Cryptography
- [findings or "none found"]

### Top Security Recommendations
1. [most critical fix needed]
2. [second priority]
3. [third priority]

### Positive Security Practices
- [list any good security practices already in place — gives credit and context]
```
