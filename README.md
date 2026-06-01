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

| Model | Directory |
|-------|-----------|
| Anthropic Claude Opus 4.8 | [`opus-4.8/`](./opus-4.8) |
| OpenAI GPT-5.5 | [`gpt-5.5/`](./gpt-5.5) |
| Zhipu GLM-5.1 | [`glm-5.1/`](./glm-5.1) |
| Moonshot Kimi K2.6 | [`kimi-k2.6/`](./kimi-k2.6) |

*(Add a new model by creating a top-level `<model-id>/` directory and committing it.)*

---

## Architecture at a Glance

- **Gitterm** spins up multiple **Opencode servers** inside **AWS ECS (Fargate)** — one per model
- Each ECS container is injected with **temporary AWS credentials** (via STS)
- Models use those credentials to build and deploy their own **cloud-native notetaking SaaS**
- This benchmark evaluates how effectively each model writes AWS infrastructure and application code

---

## License

MIT © 2026 AWS Notetaking Benchmark Team
