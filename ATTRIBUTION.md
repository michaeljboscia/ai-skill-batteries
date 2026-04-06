# Attribution

AI Skill Batteries draws on a broad range of sources. All skills are original synthesis — no content was copied verbatim. The sources below informed the patterns, decision trees, and anti-rationalization rules through Phase 1 (existing work discovery) and Phase 2 (quicksearch saturation) of the [skill-forge](skill-forge/) process.

## GitHub Repositories & AI Coding Rules

These repos provided initial signal on what AI coding agents get wrong and how rule-based constraints can prevent it:

- **[PatrickJS/awesome-cursorrules](https://github.com/PatrickJS/awesome-cursorrules)** — Mega-collection of .cursorrules for React, Next.js, TypeScript, Go, and more. Informed patterns across multiple skill packages.
- **[awslabs/aidlc-workflows](https://github.com/awslabs/aidlc-workflows)** — Official AWS AI-DLC rules for Cursor/Claude/Copilot. Authority source for AWS skills.
- **[continuedev/awesome-rules](https://github.com/continuedev/awesome-rules)** — Language-specific cursor rules including Go coding standards, error handling, and security patterns.
- **[Farzannajipour/cursor-react-rules](https://github.com/Farzannajipour/cursor-react-rules)** — Production-ready rules for React + Next.js including Server Components and accessibility.
- **[PaulDuvall/centralized-rules](https://github.com/PaulDuvall/centralized-rules)** — Multi-tool (Claude/Cursor/Copilot/Gemini) 4D cloud architecture rules.
- **[tonynguyennvt/cursor-rules-awesome](https://github.com/tonynguyennvt/cursor-rules-awesome)** — AWS/Azure/GCP coding standards for AI assistants.
- **[sanjeed5/awesome-cursor-rules-mdc](https://github.com/sanjeed5/awesome-cursor-rules-mdc)** — MDC-format cursor rules including AWS Amplify Gen 2 and ECS guidelines.
- **[virastack/ai-rules](https://github.com/virastack/ai-rules)** — AI-native architecture kit for React with Cursor rules.
- **[rsaz/PythonCodingGuidelines](https://github.com/rsaz/PythonCodingGuidelines)** — Python readability and maintainability guidelines.
- **[jsonallen/example-ai-coding-rules](https://github.com/jsonallen/example-ai-coding-rules)** — Customizable rule templates for Cursor/Claude. Informed anti-rationalization patterns.
- **[wpfleger96/ai-rules](https://github.com/wpfleger96/ai-rules)** — Consolidated AI coding agent configs with symlinks pattern.
- **[ixartz/Next-js-Boilerplate](https://github.com/ixartz/Next-js-Boilerplate)** — AGENTS.md convention for Claude Code, Codex, Cursor, Copilot.
- **[block/ai-rules](https://github.com/block/ai-rules)** — Cross-agent rule distribution CLI.
- **[greensock/gsap-skills](https://github.com/greensock/gsap-skills)** — Official GreenSock AI skills (8 skills). Our GSAP package complements rather than replaces these.
- **[supabase/supabase](https://github.com/supabase/supabase)** — Official Supabase agent-skills directory for Claude Code, Cursor, and Copilot.
- **[cursor.directory](https://cursor.directory)** and **[cursorrules.org](https://cursorrules.org)** — Community cursor rules collections.

## Style Guides & Best Practice References

- **[100go.co](https://100go.co)** (100 Go Mistakes) — Direct source for Go anti-rationalization rules.
- **[Uber Go Style Guide](https://github.com/uber-go/guide)** — Go naming, interface, and error handling conventions.
- **[Dagster Python Style Guide](https://dagster.io)** — Production Python patterns: keyword args, magic method performance, LBYL.
- **[Google Python Style Guide](https://google.github.io/styleguide/pyguide.html)** — Import conventions, naming, module structure.
- **[SecureCodeWarrior](https://www.securecodewarrior.com)** — Security-focused anti-patterns for AI-generated code across languages.
- **[pavi2410.com](https://pavi2410.com)** — Post-React-Compiler guidelines for AI agents.
- **[Terraform Best Practices](https://terraform-best-practices.com)** — Naming, variable descriptions, file structure for IaC skills.

## Official Documentation

The following official documentation was extensively referenced during quicksearch (Phase 2) and deep research (Phase 3):

- **AWS:** AWS Documentation, Well-Architected Framework, service-specific best practices
- **GCP:** Google Cloud Documentation, Architecture Framework, IAM/WIF best practices
- **Rust:** The Rust Book, Rust Reference, Rustonomicon, Rust API Guidelines
- **Python:** Python Documentation, PEPs (544, 621, 647, 649, 654, 660, 735, 742), typing module reference
- **Go:** Effective Go, Go Blog, Go standard library documentation
- **React:** React documentation (react.dev), React Server Components RFC
- **Next.js:** Next.js documentation (nextjs.org/docs), Vercel best practices, AI Coding Agents guide
- **FastAPI:** FastAPI documentation (tiangolo.com), Starlette reference
- **SQLAlchemy:** SQLAlchemy 2.0 documentation, migration guides from 1.x
- **Tailwind CSS:** Tailwind CSS v4 documentation, upgrade guides
- **HubSpot:** HubSpot API documentation, developer guides, date-based API versioning
- **Supabase:** Supabase documentation, PostgREST reference, RLS guides, Supabase AI prompts
- **WordPress/WPGraphQL:** WordPress REST API Handbook, WPGraphQL documentation
- **GSAP:** GreenSock documentation (gsap.com), gsapify.com community patterns
- **Lottie:** lottie-web documentation, dotlottie-react, Airbnb Lottie specification

## Libraries & Tools

These tools were referenced for their specific patterns and best practices sections:

- **[Ruff](https://github.com/astral-sh/ruff)** and **[uv](https://github.com/astral-sh/uv)** (Astral) — Python linting, formatting, and package management
- **[structlog](https://www.structlog.org)** — Structured logging patterns for Python
- **[OpenTelemetry](https://opentelemetry.io)** — Observability instrumentation patterns across languages
- **[Sentry](https://sentry.io)** — Error tracking and performance monitoring patterns
- **[Prometheus](https://prometheus.io)** — Metrics collection, histogram design, label cardinality rules
- **[httpx](https://www.python-httpx.org)** — Async HTTP client patterns
- **[Authlib](https://authlib.org)** — OAuth2/JWT client patterns with httpx integration
- **[tenacity](https://github.com/jd/tenacity)** — Retry pattern library
- **[PyJWT](https://github.com/jpadilla/pyjwt)** — JWT encoding/decoding (replaces abandoned python-jose)
- **[Polars](https://pola.rs)** — DataFrame library, lazy evaluation, query optimization
- **[Pydantic](https://pydantic.dev)** — Data validation, v2 migration patterns
- **[msgspec](https://jcristharif.com/msgspec)** — High-performance serialization
- **[psycopg3](https://www.psycopg.org)** — Async PostgreSQL driver patterns
- **[Alembic](https://alembic.sqlalchemy.org)** — Database migration patterns
- **[Hypothesis](https://hypothesis.readthedocs.io)** — Property-based testing for Python
- **[uvloop](https://github.com/MagicStack/uvloop)** — High-performance asyncio event loop

## AI-Assisted Research

- **Gemini Deep Research** — Used during Phase 3 of skill-forge to generate 3,000–8,000 word technical references with runnable code examples for each skill domain. These informed the final skill synthesis but were not used verbatim.
- **Gemini Search** — Used during Phase 2 quicksearch saturation for ecosystem-specific, citation-backed patterns across all domains.

## Built With

Built with [Claude Code](https://claude.ai/code) by [Anthropic](https://anthropic.com). The [skill-forge](skill-forge/) factory process, pressure testing methodology, and anti-rationalization framework were developed iteratively through production use.

## License

All skills in this repository are released under the [MIT License](LICENSE). Attribution is appreciated but not required.
