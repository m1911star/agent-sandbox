# OMP Sandbox

Run [OMP (Oh My Pi)](https://github.com/can1357/oh-my-pi) with clean configuration and your Magpie gateway. The image uses Bun 1.4.4. It does not import your host `agent.db` or OMP settings.

From the Agent Sandbox checkout, [export the Magpie URL and key](../../README.md#quick-start), then run:

```bash
./sandbox up omp
# In the container shell:
omp
```

OMP uses the `magpie` provider in `~/.omp/agent/models.yml` and the default model role in `~/.omp/agent/config.yml`. The provider uses the OpenAI Responses API and reads `MAGPIE_API_KEY`, so OMP does not use this key to authenticate its built-in OpenAI cloud models. The default model is `magpie/auto/gpt-6.1-sol` with reasoning disabled. Set `MAGPIE_MODEL` to a different Magpie model ID without the `magpie/` prefix when you create a sandbox.

Change either file inside the container to try other settings. `docker start -ai sandbox-omp` preserves the files. If either file is missing at startup, the sandbox initializes that file from the original container environment.

Pass a project path to `./sandbox up omp` only if you want a read-write mount at `/workspace`. See [network and environment settings](../../README.md#network-and-environment) if OMP cannot reach Magpie.
