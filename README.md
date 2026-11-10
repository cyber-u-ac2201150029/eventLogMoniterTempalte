# EventLogFile Collector PoC — Salesforce Metadata Deployment Template

## Overview

This repository contains a metadata template for reproducing the following configuration, originally retrieved from a Salesforce Developer Edition (DE) org, in another DE org:

- **Event Monitoring:** Enable Event Log File generation.
- **External Client App:** Define an OAuth client for retrieving `EventLogFile` data through the Salesforce REST API.
- **Client Credentials Flow:** Configure the Run As user in the target org.

Keep an unmodified backup of the original retrieved metadata. **Maintain the reusable template separately from the generated, deployment-ready metadata.**

## 1. Metadata structure

```text
force-app/main/default/
├── externalClientApps/
│   └── @@APP_API_NAME@@.eca-meta.xml
├── extlClntAppOauthSettings/
│   └── @@APP_API_NAME@@_oauth.ecaOauth-meta.xml
├── extlClntAppOauthPolicies/
│   └── @@APP_API_NAME@@_oauthPlcy.ecaOauthPlcy-meta.xml
└── settings/
    ├── Event.settings-meta.xml
    └── ExternalClientApp.settings-meta.xml
```

The three filenames containing `@@...@@` are **template filenames**, not deployable Salesforce metadata names. Replace their placeholders before deployment.

| File | Purpose |
| --- | --- |
| `Event.settings-meta.xml` | Org-level event settings, including `enableEventLogGeneration` |
| `ExternalClientApp.settings-meta.xml` | Org-level External Client App settings |
| `@@APP_API_NAME@@.eca-meta.xml` | External Client App definition |
| `@@APP_API_NAME@@_oauth.ecaOauth-meta.xml` | OAuth scopes, OAuth link, and related configuration |
| `@@APP_API_NAME@@_oauthPlcy.ecaOauthPlcy-meta.xml` | Client Credentials Flow, Run As user, IP policy, and other OAuth policies |

**Important:** The original archive does not contain `ExtlClntAppGlobalOauthSettings` (Global OAuth Settings). If the goal is to create an independent OAuth consumer in each target org, verify the required Global OAuth Settings metadata and deployment procedure for the applicable Salesforce API version before deploying.

## 2. Placeholder and naming conventions

Use `@@` as the placeholder delimiter. Underscores (`_`) are already part of API names and fixed filename suffixes, so they are not used to delimit placeholders.

| Placeholder | Description | Example replacement |
| --- | --- | --- |
| `@@APP_API_NAME@@` | External Client App API name in the target org | `MyEventLogCollector` |
| `@@RUN_AS_USERNAME@@` | **Salesforce Username** of the Client Credentials Flow Run As user in the target org | `target-user@example.invalid` |

The suffixes `_oauth` and `_oauthPlcy` are **fixed naming conventions**. There is no separate `@@OAUTH_POLICY_NAME@@` placeholder.

| Location | Template | Example after substitution |
| --- | --- | --- |
| App metadata filename | `@@APP_API_NAME@@.eca-meta.xml` | `MyEventLogCollector.eca-meta.xml` |
| OAuth Settings filename | `@@APP_API_NAME@@_oauth.ecaOauth-meta.xml` | `MyEventLogCollector_oauth.ecaOauth-meta.xml` |
| OAuth Policy filename | `@@APP_API_NAME@@_oauthPlcy.ecaOauthPlcy-meta.xml` | `MyEventLogCollector_oauthPlcy.ecaOauthPlcy-meta.xml` |
| `<externalClientApplication>` | `@@APP_API_NAME@@` | `MyEventLogCollector` |
| OAuth Settings `<label>` | `@@APP_API_NAME@@_oauth` | `MyEventLogCollector_oauth` |
| OAuth Policy `<label>` | `@@APP_API_NAME@@_oauthPlcy` | `MyEventLogCollector_oauthPlcy` |
| `<clientCredentialsFlowUser>` | `@@RUN_AS_USERNAME@@` | Username of an active user in the target org |

### OAuth Policy XML example

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ExtlClntAppOauthConfigurablePolicies xmlns="http://soap.sforce.com/2006/04/metadata">
    <clientCredentialsFlowUser>@@RUN_AS_USERNAME@@</clientCredentialsFlowUser>
    <externalClientApplication>@@APP_API_NAME@@</externalClientApplication>
    <ipRelaxationPolicyType>Enforce</ipRelaxationPolicyType>
    <isClientCredentialsFlowEnabled>true</isClientCredentialsFlowEnabled>
    <isGuestCodeCredFlowEnabled>false</isGuestCodeCredFlowEnabled>
    <isTokenExchangeFlowEnabled>false</isTokenExchangeFlowEnabled>
    <label>@@APP_API_NAME@@_oauthPlcy</label>
    <permittedUsersPolicyType>AllSelfAuthorized</permittedUsersPolicyType>
    <refreshTokenPolicyType>SpecificInactivity</refreshTokenPolicyType>
    <refreshTokenValidityPeriod>30</refreshTokenValidityPeriod>
    <refreshTokenValidityUnit>Days</refreshTokenValidityUnit>
    <requiredSessionLevel>STANDARD</requiredSessionLevel>
</ExtlClntAppOauthConfigurablePolicies>
```

These policy values reflect the retrieved configuration. Review them against the target org's security requirements rather than assuming they are appropriate everywhere.

## 3. Handling `oauthLink`

OAuth Settings retrieved from the source org may include an `oauthLink` pointing to that org's OAuth consumer.

**When deploying an independent OAuth consumer to another DE org, remove the entire `<oauthLink>...</oauthLink>` element from the template. Do not replace it with an empty `<oauthLink/>` element.**

Keep the following **English XML comment** at the removal location in `extlClntAppOauthSettings/@@APP_API_NAME@@_oauth.ecaOauth-meta.xml`:

```xml
<!--
    The oauthLink element is intentionally omitted to prevent
    referencing the OAuth consumer from the source Salesforce org.

    When this External Client App is deployed to another org,
    a new OAuth consumer and an org-specific OAuth link are expected
    to be created when the required Global OAuth Settings and
    related deployment requirements are satisfied.

    After deployment, retrieve the OAuth Settings metadata from
    the target org to verify its newly generated oauthLink value.
    The local template file is not automatically updated by deployment.

    IMPORTANT:
    Do not restore the source org's oauthLink.
    Do not add an empty or self-closing oauthLink element
    (e.g., <oauthLink/>).
    The oauthLink element must be completely omitted from the
    deployment template, including its opening and closing tags.
-->
```

These instructions apply to the **independent-consumer deployment approach**. They should not be confused with a deployment approach that deliberately links to an existing OAuth consumer.

## 4. Other org-specific metadata to review

The retrieved metadata may contain org-specific information beyond the two primary placeholders. Before deployment, review at least the following:

- **`<orgScopedExternalApp>`** in `externalClientApps/*.eca-meta.xml`: May contain an identifier tied to the source org. Do not blindly copy it to a different org; verify the correct handling for the chosen deployment approach.
- **`<contactEmail>` and `<contactPhone>`** in the same file: Replace source-org contact details with appropriate target-org values. Add `@@CONTACT_EMAIL@@` and `@@CONTACT_PHONE@@` placeholders if needed.
- **`<oauthLink>`** in OAuth Settings: Omit the element entirely when using the independent-consumer approach described above.
- **`<clientCredentialsFlowUser>`** in OAuth Policy: Replace it with the Username of an active user in the target org.
- **`settings/*.settings-meta.xml`**: Retrieved settings files may contain unrelated org configuration. Review differences carefully before deploying them to another org.

The retrieved OAuth scopes were `Api, RefreshToken, Lightning`. Review whether all of these are necessary for the EventLogFile collection PoC and apply the target org's least-privilege requirements.

## 5. Deployment procedure for another DE org

1. Back up the original retrieved metadata and this README.
2. Copy the **template** into a separate working directory for the target org.
3. Replace `@@APP_API_NAME@@` and `@@RUN_AS_USERNAME@@` throughout both XML contents and filenames.
4. Confirm that the `oauthLink` element is completely absent from the independent-consumer template.
5. Review and adjust `orgScopedExternalApp`, contact details, Global OAuth Settings, and other org-specific values.
6. Confirm that no placeholders remain and that metadata references match the final filenames.
7. Deploy to the target DE org and validate OAuth authentication and EventLogFile access.

### Check for unresolved placeholders (Bash)

```bash
grep -RIn '@@' force-app/main/default || true
find force-app/main/default -type f -name '*@@*' -print
```

Both commands should return **no matching files or lines** for the deployment-ready metadata.

### Salesforce CLI deployment example

Specify the target org explicitly:

```bash
sf project deploy start \
  --source-dir force-app/main/default/settings/Event.settings-meta.xml \
  --target-org TARGET_ORG_ALIAS
```

Deploy the External Client App metadata separately after verifying the required related components and Global OAuth Settings. **Do not deploy the entire `force-app` directory while template placeholders remain unresolved.**

### Post-deployment verification

- In the target org's **Event Monitoring Settings**, verify that **Generate Event Log Files** is enabled.
- Confirm that the External Client App exists with the intended OAuth scopes and Client Credentials Flow configuration.
- Verify that the Run As user is the intended user in the target org.
- Obtain an OAuth token using the **target org's** Consumer Key and Consumer Secret.
- Run an SOQL query against `EventLogFile` (`HTTP 200` can indicate successful authentication and querying even when the result contains zero records).
- Retrieve OAuth Settings again from the target org and verify the target-specific `oauthLink`, if an independent consumer has been created.

## 6. Security and source control

- **Never commit Consumer Secrets, access tokens, or personal user information to Git or a public repository.**
- `ExtlClntAppGlobalOauthSettings` can contain sensitive OAuth credentials. Inspect its contents before retrieving, storing, or sharing it.
- Store per-org credentials separately from reusable metadata templates in an appropriate secure secret store.
- Rotate any Consumer Secret previously exposed in chat, logs, or shared documents.
- Handle backups containing source-org IDs, OAuth links, usernames, or contact details as sensitive internal artifacts.

---

**Scope:** This README is a reusable metadata template guide and deployment checklist, not a guarantee of successful deployment. The exact requirements for creating an independent OAuth consumer and deploying each metadata component depend on the Salesforce API version, target-org capabilities, and deployment approach. Validate the resulting configuration in a nonproduction org.

## 8. Git line-ending and local-file conventions (Windows / Code Builder)

This repository includes `.gitattributes` and `.gitignore` for a mixed Windows and Linux workflow.

- `.gitattributes` keeps Salesforce XML, JSON, Markdown, and shell scripts at **LF** and Windows `.bat`/`.cmd` files at **CRLF** in the working tree. Files are normalized to LF in Git.
- PowerShell scripts (`.ps1`, `.psm1`, `.psd1`) use CRLF in the working tree. **Windows PowerShell 5.1** may require UTF-8 **with BOM** for scripts containing non-ASCII characters; `.gitattributes` does not set a file's encoding or BOM.
- `.gitignore` excludes Salesforce local state (`.sf/`, `.sfdx/`), dependencies, temporary OAuth responses, archives, and common secret-file formats. **It does not detect secrets embedded in tracked metadata.** Review XML values before staging or pushing.
- `force-app/` is intentionally **not** ignored because it contains the metadata template. Only commit sanitized template content; generate deployable, org-specific content separately.

After adding or changing `.gitattributes`, normalize previously tracked files once (review the diff first):

```bash
git add --renormalize .
git diff --cached --check
git diff --cached --stat
```

To verify Git's selected attributes:

```bash
git check-attr text eol -- force-app/main/default/settings/Event.settings-meta.xml
```

Avoid committing raw retrieved OAuth credentials, run-as usernames, org IDs, or source-org links. If a secret has already been committed, deleting it in a later commit does not remove it from Git history; rotate the secret and address the repository history as appropriate.