# AWS Notetaking SaaS — Model Benchmark Suite

A benchmark that tests how effectively AI models write **AWS cloud-native code** when given an AWS account with **temporary credentials**.

**Gitterm** makes this possible by orchestrating **Opencode** servers across cloud providers, including **Amazon ECS**, where each model gets its own isolated instance with injected AWS credentials.

Each model operates in its own directory. Click through below to see their implementations.

---

## Stack & Tools

| Tool | Link | Role |
|------|------|------|
| **Gitterm** | [https://gitterm.dev](https://gitterm.dev) | Orchestrates Opencode servers across cloud providers (AWS ECS, etc.) |
| **AWS** | [https://aws.amazon.com](https://aws.amazon.com) | Cloud infrastructure where models deploy their notetaking SaaS |
| **Opencode** | [https://opencode.ai](https://opencode.ai) | The AI engineering platform running inside each ECS container |

---

## Model Entries

Each model has its own directory with its code, infrastructure, and README.

| Model | Directory | PR |
|-------|-----------|----|
| Anthropic Claude Opus 4.8 | [`opus-4.8/`](./opus-4.8) | [#1](https://github.com/OpeOginni/aws-notetaking-saas/pull/1) |
| OpenAI GPT-5.5 | [`gpt-5.5/`](./gpt-5.5) | [#2](https://github.com/OpeOginni/aws-notetaking-saas/pull/2) |
| Zhipu GLM-5.1 | [`glm-5.1/`](./glm-5.1) | |
| Moonshot Kimi K2.6 | [`kimi-k2.6/`](./kimi-k2.6) | |

---

## Model Metrics & Results

| Metric | GPT-5.5 | Opus 4.8 |
|--------|---------|----------|
| **Time** | 60 mins | 37 mins |
| **Tokens Used** | 71,400 | 103,000 |
| **Cost** | $4.12 | $5.18 |
| **Prompts Needed** | 2 (needed a follow-up for image feature) | 1 (one-shot) |
| **Landing Page** | Great | Not as polished |
| **Note Flow (create → dashboard → edit)** | Needs significant developer/designer work | Better flow |

---

## Observations & Patterns

A few consistent behaviors stood out across all models:

- **No Docker inside ECS** — Models recognized they couldn't run Docker within the ECS containers and cleanly pivoted to **AWS CodeBuild** for container image builds.
- **Reproducible deployments** — The prompt explicitly asked models to make their deployment **reproducible**, which is why each one provided **provisioning/deployment scripts**. This made it straightforward to spin all resources and services down after testing.

> **Tip for users:** Encourage your models to produce reproducible deployment scripts too. It makes teardown, re-testing, and sharing results much easier on your end.

---

## Architecture at a Glance

- **Gitterm** spins up multiple **Opencode servers** inside **AWS ECS (Fargate)** — one per model
- Each ECS container is injected with **temporary AWS credentials** (via STS)
- Models use those credentials to build and deploy their own **cloud-native notetaking SaaS**
- This benchmark evaluates how effectively each model writes AWS infrastructure and application code

---

## License

MIT © 2026 AWS Notetaking Benchmark Team
