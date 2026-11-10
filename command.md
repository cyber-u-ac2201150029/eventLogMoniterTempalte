# Implementation Task: Salesforce Environment Support for EventLogFile Collector Template

## Role and objective

You are an engineer working on an **existing feature branch** of the `eventLogMoniterTempalte` Salesforce DX repository. Implement a small, backward-compatible enhancement so the EventLogFile collector workflow can be configured and documented for **Production, Developer Edition (DE), and Sandbox** organizations without confusing login endpoints, org aliases, or My Domain URLs.

**Work on the currently checked-out branch only. Do not create or switch branches.** Inspect the actual repository contents before editing; do not assume filenames or directory layouts beyond what exists.

## Existing functionality to preserve

The repository includes a Salesforce External Client App metadata deployment template, currently using:

- `templates/force-app/main/default/` as the source template directory.
- `scripts/bash/render-template.sh` to render template XML and filenames, **using Bash and standard Unix tools, with no Python runtime dependency**.
- Placeholders `@@APP_API_NAME@@`, `@@RUN_AS_USERNAME@@`, and `@@CONTACT_PHONE@@` (verify in the checked-out script and update it if any documented placeholder is missing).
- Output paths of the form `build/<ORG_ALIAS>/<APP_API_NAME>/force-app/`, supporting multiple applications per target org.
- An `ExtlClntAppGlobalOauthSettings` template that creates an independent OAuth consumer per target org. Do not reuse a retrieved `consumerKey` or `consumerSecret`.
- Omission of **active** `oauthLink` and `orgScopedExternalApp` XML elements from templates used for first deployment. The explanatory XML comments should remain.
- No overwrite of existing generated output, and failure on unresolved `@@...@@` placeholders.

The following has already been confirmed manually against a DE org (Metadata API v68.0): all six metadata components passed `sf project deploy start --dry-run`, and the subsequent actual deployment succeeded. **Do not disturb this working deployment pattern.**

## Core design distinction — do not conflate these

1. `ORG_ALIAS` is a **local Salesforce CLI alias and output directory key**; it is not a Salesforce domain and must not be converted into one.
2. `RUN_AS_USERNAME` is a Salesforce user name; it is not necessarily the External Client App contact email, and is not a login URL.
3. `SF_BASE_URL` is the absolute HTTPS origin of the target Salesforce org, without trailing `/`, e.g.:
   - Production: `https://acme.my.salesforce.com`
   - DE: `https://mydev.develop.my.salesforce.com`
   - Sandbox: `https://acme--uat.sandbox.my.salesforce.com`
4. Salesforce CLI authentication may also use the generic login sites `https://login.salesforce.com` (Production / DE) or `https://test.salesforce.com` (Sandbox), subject to the org login policy. **Do not substitute those generic login domains blindly for Client Credentials OAuth or subsequent REST API calls.** Prefer the org-specific My Domain for OAuth client credentials.
5. The Salesforce Metadata API deployment process (`sf project deploy start --source-dir ... --target-org ...`) does not require adding a Salesforce URL placeholder to External Client App XML. Keep URL configuration separate unless a concrete metadata field requires it.

## Requested work

### A. Inspect and document the current repository

- Examine `README.md`, `.gitattributes`, `.gitignore`, `scripts/bash/render-template.sh`, template XML and any existing Windows BAT/PowerShell collector scripts.
- Report inconsistencies between README, CLI usage, placeholder support, and the actual template files, including the Global OAuth Settings template.
- Do not add a nonexistent BAT collector script merely to demonstrate a URL change. If the collector is external to this repository, provide a safe, copy-pasteable example in documentation instead.

### B. Implement environment-aware URL configuration, with minimal change

- Keep `render-template.sh`'s existing positional arguments **and behavior compatible**, especially `ORG_ALIAS APP_API_NAME RUN_AS_USERNAME CONTACT_PHONE [TEMPLATE_DIR] [OUTPUT_DIR]`, if that is what the checked-out branch implements.
- Do **not** make Production/DE/Sandbox a required new positional argument unless absolutely necessary. The template renderer need not know a URL in order to generate metadata.
- Add documentation or a lightweight, dependency-free helper/example for configuring `SF_BASE_URL` in collector code. If collector code exists, refactor it to consume an explicit full `SF_BASE_URL` rather than assembling `https://%instance%.salesforce.com` from a partial hostname.
- Use the same `SF_BASE_URL` for `.../services/oauth2/token` and `.../services/data/vXX.X/query`; where possible, confirm the intended API endpoint and avoid hardcoding `login.salesforce.com` as the REST host.
- For the collector, **do not infer a URL from `ORG_ALIAS`**. Use an explicit URL supplied by configuration, and validate `https://` and a non-empty hostname. Distinguish between a target-org alias for deploy and the actual org URL for OAuth.
- Do not change unrelated OAuth metadata, security policies, EventSettings, or Salesforce API version solely for this task.

### C. Provide reproducible commands per environment

In `README.md`, add a concise environment matrix covering Production, DE, and Sandbox:

- Typical My Domain URL formats; clarify that names are illustrative and may vary.
- `sf org login web --instance-url <appropriate URL> --alias <alias>` examples.
- Rendering a template for an alias and Run As user (plus contact phone if required).
- Checking the authenticated org: `sf org list`, `sf org display --target-org <alias>`.
- Deploy validation using `sf project deploy start --source-dir <generated force-app path> --target-org <alias> --dry-run --test-level NoTestRun --wait 10`.
- Explicitly state that `sf project deploy preview` can fail on an org without source tracking (`NonSourceTrackedOrgError`); `deploy start --dry-run` performs the needed server-side validation.
- Explain that a successful deployment does not prove Client Credentials authentication; a separate token and EventLogFile query smoke test is needed.

### D. Security and portability requirements

- Never include actual Consumer Keys, Client Secrets, bearer tokens, organization IDs, real user names, or contact phone numbers in documentation, code, output, or tests. Use clearly fictional values / `example.invalid`.
- Keep retrieved Global OAuth Settings with secrets out of Git. Validate that `.gitignore` covers build artifacts and temporary OAuth responses; avoid broad rules that accidentally ignore source templates.
- Preserve XML UTF-8 and LF line endings for `.xml`, `.md`, and `.sh` via `.gitattributes`. Do not introduce CRLF into shell scripts; Windows `.bat` files can use CRLF and CP932 if the existing workflow requires it.
- Do not introduce Python, Node, jq, or other new runtime dependencies solely for this change. Use Bash and standard tools available in Windows Git Bash and Linux IDE environments.
- Ensure the renderer still correctly replaces placeholders in **both filenames and XML content**, and still detects unresolved placeholders and refuses to overwrite existing output.
- Do not deploy to any Salesforce org without explicit user instruction. Work locally and run local tests; provide deployment commands but do not execute real deployments.

## Acceptance criteria

1. Existing template rendering works exactly as before for a DE org, including Global OAuth Settings, OAuth policy, and contact phone.
2. The same renderer works for a Sandbox alias and for a Production alias without assuming that the alias is a hostname.
3. Output paths remain isolated by alias and application name, for example `build/sandbox-uat/MyEventLogCollector/force-app/` and `build/prod/MyEventLogCollector/force-app/`.
4. No `@@...@@` placeholders remain in rendered filenames or XML (excluding intentionally documented examples outside generated metadata).
5. XML has no active `oauthLink`, `orgScopedExternalApp`, `consumerKey`, or `consumerSecret` in **new-consumer templates**; comments explaining the omission are allowed.
6. Scripts pass `bash -n`; perform smoke tests for 2 different aliases and app names using a temporary output directory, and verify that attempts to re-render into an existing target fail safely.
7. README explains environment-specific URL configuration, the difference between `preview` and server-side `--dry-run`, deployment, and the post-deploy OAuth smoke test.
8. Show the resulting changed-file list, concise diff summary, exact commands used for local tests, and any outstanding Salesforce-side verification. Do not claim actual deployment success unless performed by the user.

## Suggested verification commands (adjust to actual tree)

```bash
bash -n scripts/bash/render-template.sh
find templates/force-app/main/default -type f -print | sort
git diff --check
git status --short
```

If appropriate, add a small Bash regression-test script that runs the renderer against a temporary directory and validates filenames and placeholder expansion without contacting Salesforce.

## Deliverables

- Minimal modifications to the existing scripts, **only if genuinely needed**.
- Updated `README.md` with Production / DE / Sandbox setup and operational examples.
- Optional small Bash-only regression tests or example environment configuration (without credentials).
- An implementation summary explaining what changed, why, what was tested, and any remaining manual steps.

**Priority:** Preserve the already-successful six-component Metadata API deployment workflow; make environment-specific connections explicit, safe, and repeatable rather than redesigning the metadata template.
