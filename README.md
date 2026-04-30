# SAIAA — Secure AI Agentic Assistant

SAIAA is a self-hosted agentic AI assistant designed with security as a first-class concern. It pairs the [ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw) agent runtime with a hardened [LiteLLM](https://github.com/BerriAI/litellm) gateway that performs **prompt-injection screening** on every request and **complexity-based model routing** to send each prompt to the smallest model that can answer it. Tools are exposed through [MCPJungle](https://github.com/mcpjungle/MCPJungle), a centralized MCP (Model Context Protocol) server registry that keeps third-party tool integrations isolated, auditable, and easy to add or revoke.

The repository ships two deployment paths: a single-host **Docker Compose** stack for local development, and a **Terraform + Ansible** pipeline that provisions hardened Ubuntu 24.04 VMs on OpenStack (tested against OVH public cloud).

> Hackathon submission by Team-12-AI.

---

## Why "secure"?

Most agent stacks send raw user input straight to the model and trust whatever tools are wired up. SAIAA layers four defenses in front of that:

1. **Llama Guard 4 pre-call guardrail.** Every prompt is scanned by a dedicated `meta-llama/llama-guard-4-12b` model *before* the main model sees it. Requests that match prompt-injection or unsafe-content categories are rejected at the gateway. The guardrail is attached globally via a `safety-baseline` policy with `scope: "*"`, so it cannot be bypassed by selecting a different model.
2. **Complexity-aware routing.** A scoring function (token count, code presence, reasoning markers, technical terms, multi-step patterns, etc.) classifies each prompt into one of four tiers and routes accordingly. Cheap prompts never touch expensive frontier models, and expensive prompts get the reasoning capacity they need.
3. **Centralized MCP registry.** Tool servers (calculator, email, Trello, etc.) are registered with MCPJungle rather than connected to the agent directly. Credentials live in registry-side config, the agent only sees the registry, and tools can be added or removed without touching the agent.
4. **Hardened host.** The Terraform path provisions VMs with `fail2ban`, key-only SSH (passwords disabled via cloud-init), authorized keys pulled from explicit GitHub identities, and Docker installed via the upstream `geerlingguy.docker` role.

---

## Architecture

```
                ┌────────────────────────────────────────────────────┐
                │                       Host                        │
                │                                                    │
   user ──────► │  ZeroClaw ──► LiteLLM ──► OpenRouter ──► (models) │
                │   (agent)     │  │                                 │
                │               │  └─► Llama Guard 4 (pre-call)      │
                │               │                                    │
                │               └─► smart-router (4 tiers)           │
                │                                                    │
                │  ZeroClaw ──► MCPJungle ──► [calc, email, trello]  │
                │                  │                                 │
                │                  └─► Postgres 17                   │
                └────────────────────────────────────────────────────┘
```

| Service       | Image                                            | Port  | Purpose                                                |
|---------------|--------------------------------------------------|-------|--------------------------------------------------------|
| `zeroclaw`    | `hauptj/zeroclaw-debian:0.6.9`                   | 42617 | Agent runtime / gateway exposed to the user            |
| `litellm`     | `hauptj/litellm:v1.83.9-llamaguard4-dev`         | 4000  | Model gateway with Llama Guard + complexity routing    |
| `mcpjungle`   | `ghcr.io/mcpjungle/mcpjungle:latest-stdio`       | 8080  | MCP server registry                                    |
| `db`          | `postgres:17`                                    | 5432  | Persistence for MCPJungle                              |

### Routing tiers

LiteLLM exposes a single `smart-router` model that classifies the prompt and dispatches to one of four backends (defined in `dev-docker/litellm-config.yaml`):

| Tier        | Score range   | Model              | Routed via OpenRouter to       |
|-------------|---------------|--------------------|--------------------------------|
| SIMPLE      | `< 0.15`      | `gpt-4o-mini`      | `openai/gpt-4o-mini`           |
| MEDIUM      | `0.15 – 0.35` | `gpt-4o`           | `openai/gpt-4o`                |
| COMPLEX     | `0.35 – 0.60` | `claude-sonnet`    | `anthropic/claude-sonnet-4.6`  |
| REASONING   | `> 0.60`      | `claude-opus`      | `anthropic/claude-opus-4.7`    |

Cross-tier fallbacks (`claude-opus → claude-sonnet → gpt-4o`) keep the gateway responsive if a provider is down. If the router cannot score a prompt, it defaults to `gpt-4o`.

---

## Repository layout

```
SAIAA/
├── README.md
├── dev-docker/                  # Local Docker Compose stack
│   ├── docker-compose.yml       # ZeroClaw + LiteLLM + MCPJungle + Postgres
│   ├── litellm-config.yaml      # Guardrail + routing config
│   ├── litellm.env              # LiteLLM master key, OpenRouter API key
│   ├── zeroclaw.env             # ZeroClaw API key
│   └── mcp/                     # MCP server definitions registered on startup
│       ├── calc.json.pub        # @wrtnlabs/calculator-mcp
│       ├── email.json.pub       # mcp-email-server (IMAP/SMTP)
│       ├── trello-apps.json.pub # @Hint-Services/mcp-trello
│       ├── trello-net.json      # @Hint-Services/mcp-trello (events board)
│       └── register_servers.sh  # Polls MCPJungle, then registers each server
└── dev/                         # OpenStack VM provisioning
    ├── main.tf                  # Compute instance + cloud-init + provisioners
    ├── variables.tf             # Cloud, image, flavor, SSH inputs
    ├── outputs.tf               # Public IPv4 / IPv6 of provisioned VMs
    └── ansible/
        ├── playbook.yml         # Installs Docker + fail2ban
        ├── ssh_keys.yml         # Pulls authorized keys from GitHub
        ├── requirements.yml     # geerlingguy.docker, robertdebock.fail2ban
        ├── docker-compose.yml   # Same stack, deployed to the VM
        └── brock.pub            # Additional authorized SSH key
```

Files ending in `.pub` are public templates with secrets redacted; the un-suffixed `.json` files (e.g. `trello-net.json`) are loaded at runtime and **must be populated with your own credentials before bringing the stack up**.

---

## Quick start — Docker Compose

Requirements: Docker Engine 24+, Docker Compose v2, an [OpenRouter](https://openrouter.ai) API key.

```bash
git clone https://github.com/Team-12-AI/SAIAA.git
cd SAIAA/dev-docker

# 1. Set your own keys — DO NOT reuse the example values committed here.
$EDITOR litellm.env       # set LITELLM_MASTER_KEY and OPENROUTER_API_KEY
$EDITOR zeroclaw.env      # set API_KEY (must match LITELLM_MASTER_KEY)

# 2. Fill in MCP server credentials (Trello, email, etc.)
cp mcp/calc.json.pub        mcp/calc.json
cp mcp/email.json.pub       mcp/email.json
cp mcp/trello-apps.json.pub mcp/trello-apps.json
$EDITOR mcp/email.json mcp/trello-apps.json mcp/trello-net.json

# 3. Bring it up
docker compose up -d

# 4. Hit the gateway
curl http://localhost:42617/health
```

ZeroClaw is now reachable at `http://localhost:42617`, LiteLLM at `http://localhost:4000`, and MCPJungle at `http://localhost:8080`. The `mcpjungle` container's `post_start` hook runs `register_servers.sh`, which polls `/metrics` until the registry is ready and then registers each MCP server defined in `dev-docker/mcp/`.

### ARM64 note

The default ZeroClaw image is distroless and may exit immediately on ARM64. The `docker-compose.yml` includes a commented alternative — switch the `zeroclaw` service to `ghcr.io/zeroclaw-labs/zeroclaw:debian` (or the local Debian build) if you hit this.

---

## Quick start — OpenStack (Terraform + Ansible)

Requirements: Terraform ≥ 1.3, an `openstack` CLI config (`~/.config/openstack/clouds.yaml`) with an entry matching `cloud_name`, and an SSH keypair.

```bash
cd SAIAA/dev

# Provide values for required variables (image_id, flavor_id, external_network_id)
cat > terraform.tfvars <<EOF
image_id            = "<glance-image-id>"
flavor_id           = "<flavor-id>"
external_network_id = "<external-network-id>"
ssh_public_key_path = "~/.ssh/id_rsa.pub"
EOF

terraform init
terraform plan
terraform apply
terraform output instance_public_ipv4
```

Terraform will:

1. Boot `var.instance_count` Ubuntu 24.04 VMs (default: 2) on the cloud named in `var.cloud_name` (default `ovhbhs5`).
2. Wait for cloud-init, install Ansible, clone ZeroClaw and MCPJungle.
3. Upload the Ansible playbook and run it: installs Docker, fail2ban, and authorizes SSH keys for the GitHub users listed in `ssh_keys.yml` (`hauptj`, `jason-the-builder`, `BMatze`) plus the local `brock.pub` key.
4. Drop a `docker-compose.yml` into the `ubuntu` user's home directory, ready for `docker compose up -d`.

Defaults you'll likely want to adjust in `variables.tf`:

| Variable           | Default                | Notes                                      |
|--------------------|------------------------|--------------------------------------------|
| `cloud_name`       | `ovhbhs5`              | Must match an entry in `clouds.yaml`       |
| `instance_count`   | `2`                    | Capped at 20 by validation                 |
| `instance_name`    | `ubuntu-2404-vm`       | Used as a prefix for related resources     |
| `flavor_name`      | `d2-8`                 | OVH flavor; pick what fits your tenant     |
| `ssh_allowed_cidr` | `0.0.0.0/0`            | **Restrict this** before exposing in prod  |

---

## Configuration reference

### LiteLLM (`dev-docker/litellm-config.yaml`)

- `model_list` — backends for each tier plus the `llama-guard` and `smart-router` entries.
- `guardrails.llama-guard-4-pre` — pre-call guardrail; `default_on: true` and attached globally via `policy_attachments`.
- `complexity_router_config.dimension_weights` — tune scoring (defaults emphasize `codePresence`, `reasoningMarkers`, and `technicalTerms`).
- `router_settings.fallbacks` — cross-tier failover chains.

### ZeroClaw (`dev-docker/zeroclaw.env`, `docker-compose.yml`)

- `API_KEY` — must match the LiteLLM master key.
- `API_URL` — points at the LiteLLM service (`http://litellm:4000/v1` inside the compose network).
- `PROVIDER=custom:http://litellm:4000/v1` — sends all calls through the LiteLLM proxy rather than directly to a vendor.
- `ZEROCLAW_GATEWAY_PORT` (default `42617`) and `HOST_PORT` for the host-side mapping.

### MCP servers

Each `*.json` file under `dev-docker/mcp/` is registered with MCPJungle on startup. The shipped set:

- **calc** — `@wrtnlabs/calculator-mcp` (no credentials).
- **zerolib-email** — `mcp-email-server` over IMAP/SMTP; expects account, host, and password env vars.
- **trello-applications / trello-events** — `@Hint-Services/mcp-trello`; expects `trelloApiKey`, `trelloToken`, `trelloBoardId`.

To add another server, drop a new `<name>.json` into `dev-docker/mcp/`, append the name to the `mcp_server_list` array in `register_servers.sh`, and restart the `mcpjungle` container.

---

## Security notes

- **Rotate the example keys.** The `.env` files in this repo contain placeholder/test values that should be treated as compromised. Generate a fresh `LITELLM_MASTER_KEY` (any random string), use your own `OPENROUTER_API_KEY`, and replace any Trello tokens before pushing this anywhere.
- **Don't commit secrets.** Move real credentials into `.env` files that are listed in `.gitignore`, or into a secret manager. The committed `*.json.pub` files are deliberately the redacted variants — keep it that way.
- **Tighten `ssh_allowed_cidr`** before applying the Terraform stack outside a lab.
- **Llama Guard is not infallible.** It's a strong default filter, not a substitute for treating model output as untrusted. Anything the agent calls (especially the email and Trello tools) should be sandboxed accordingly.

---

## Troubleshooting

- **MCP servers don't register.** Check `dev-docker/mcp/register.log` — `register_servers.sh` writes the output of every `mcpjungle register` call there. The most common cause is bad credentials in a `*.json` file.
- **LiteLLM rejects every request.** Verify `OPENROUTER_API_KEY` in `litellm.env` and confirm your OpenRouter account has access to the listed models, especially `meta-llama/llama-guard-4-12b` (the guardrail will fail-closed if it can't reach the guard model).
- **ZeroClaw exits immediately.** You're probably on ARM64 with the distroless image — switch to the Debian variant as described above.
- **Terraform `remote-exec` hangs.** Cloud-init is still installing prerequisites; the provisioner waits up to 5 minutes via `cloud-init status --wait`. If it consistently times out, check the VM console for snap/apt errors.

---

## Acknowledgments

SAIAA is glue around excellent open-source projects, all of which deserve the credit:

- [ZeroClaw](https://github.com/zeroclaw-labs/zeroclaw) — agent runtime
- [LiteLLM](https://github.com/BerriAI/litellm) — model gateway, guardrails, routing
- [MCPJungle](https://github.com/mcpjungle/MCPJungle) — MCP server registry
- [Llama Guard 4](https://huggingface.co/meta-llama/Llama-Guard-4-12B) — input safety classifier
- [`geerlingguy.docker`](https://github.com/geerlingguy/ansible-role-docker) and [`robertdebock.fail2ban`](https://github.com/robertdebock/ansible-role-fail2ban) — Ansible roles
- [`@wrtnlabs/calculator-mcp`](https://www.npmjs.com/package/@wrtnlabs/calculator-mcp), [`mcp-email-server`](https://pypi.org/project/mcp-email-server/), and [`@Hint-Services/mcp-trello`](https://www.npmjs.com/package/@Hint-Services/mcp-trello) — bundled MCP tools