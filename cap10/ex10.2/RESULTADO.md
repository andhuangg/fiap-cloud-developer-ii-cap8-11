# Exercício 10.2: Scan de vulnerabilidades e correção da imagem base

Arquivos entregues:

| Arquivo | O que é |
|---|---|
| `antes/Dockerfile` | imagem deliberadamente ruim (`python:3.12` completa, sem multi-stage, root, `COPY . .`) |
| `depois/Dockerfile` | multi-stage + `gcr.io/distroless/python3-debian12:nonroot`, UID 65532 |
| `depois/.dockerignore` | exclui `.git`, `.env`, `*.pem`, `*.key`, `tests/` etc. |
| `depois/requirements.txt` | dependências atualizadas conforme o scanner |
| `relatorio-antes.txt` / `relatorio-depois.txt` | `trivy image --severity HIGH,CRITICAL` completos |
| `store-api-sbom.json` | SBOM CycloneDX 1.7 da `store-api:1.1` |
| `saidas.txt` | todos os comandos com horário e saída |

Trivy: base de vulnerabilidades atualizada em 31/10/2026.

## Diagnóstico da imagem ruim (`store-api:vuln`)

- **Tamanho:** 1,7 GB.
- **Root:** `docker run --rm store-api:vuln id` retorna `uid=0(root) gid=0(root) groups=0(root)`.
- **Vazamento pelo `COPY . .` sem `.dockerignore`:** havia um `.env` (com valores falsos) no diretório de build, e ele foi parar dentro da imagem:
  ```
  $ docker run --rm store-api:vuln cat /app/.env
  DB_PASSWORD=senha-de-producao-FAKE
  AWS_SECRET_ACCESS_KEY=FAKE-NAO-E-REAL
  ```
- **Scanner:** `store-api:vuln (debian 13.7)` com `Total: 469 (HIGH: 453, CRITICAL: 16)` no SO, mais `Python: Total: 3 (HIGH: 3)`, todas no `starlette 0.41.3` (dependência do `fastapi 0.115.6`):
  - CVE-2025-62727 (DoS via header Range), corrigida em 0.49.1
  - CVE-2026-48818 (SSRF / roubo de credencial NTLM via UNC), corrigida em 1.1.0
  - CVE-2026-54283 (limites do `request.form()` ignorados), corrigida em 1.3.1

## Correções aplicadas

1. **Multi-stage + distroless.** O builder instala as dependências num venv. A imagem final só recebe o venv e o `main.py`, sem shell, apt, pip, compiladores nem coreutils.
2. **Builder compatível com o runtime.** O Dockerfile da apostila usa `python:3.12-slim` no builder, mas o distroless debian12 traz o **Python 3.11 em `/usr/bin`**: os symlinks do venv apontariam para `/usr/local/bin/python3.12`, que não existe na imagem final. Por isso usei `debian:12-slim` + `python3-venv` no builder (mesmo interpretador e mesmo caminho do distroless).
3. **Dependências:** `fastapi 0.162.0`, `starlette 1.10.0` (fixada explicitamente, acima da 1.3.1) e `uvicorn[standard] 0.54.0`. O `pip`/`setuptools` é desinstalado do venv antes da cópia.
4. **`USER 65532:65532` numérico** e `ENTRYPOINT` em forma exec.
5. **`.dockerignore`:** o mesmo `.env` estava no diretório `depois/` e **não** entrou na imagem (`.env existe na imagem? False`).

Validação funcional da 1.1: `/health` e `/produtos` respondem; `uid 65532 gid 65532`; `docker exec ... id` falha com `executable file not found`, porque não existe nem o binário `id` (distroless).

## Tabela comparativa

| Métrica | `store-api:vuln` | `store-api:1.1` | Variação |
|---|---|---|---|
| Tamanho (`docker images`, em disco) | 1,7 GB | 147 MB | **−91,4%** |
| Tamanho (`docker image inspect .Size`) | 428,7 MB | 31,2 MB | −92,7% |
| Base | Debian 13.7 completo | distroless Debian 12.13 | |
| CVEs CRITICAL (total) | 16 | 2 | −87,5% |
| CVEs CRITICAL **corrigíveis** (`--ignore-unfixed`) | 0 | **0** | |
| CVEs HIGH (total, SO + Python) | 456 | 60 | −86,8% |
| CVEs HIGH corrigíveis | 159 | 45 | −71,7% |
| CVEs na aplicação (Python) | 3 HIGH | **0** | |
| Componentes no SBOM (CycloneDX) | 487 | **55** | −88,7% |
| UID do processo | 0 (root) | **65532** | |
| `.env` dentro da imagem | sim | não | |

Leitura honesta dos números:

- Os 2 CRITICAL e os 60 HIGH que restam estão **todos na camada do distroless** (pacotes Debian 12 como libc e openssl). As dependências Python têm 0 vulnerabilidades.
- Nenhum dos 2 CRITICAL tem correção publicada pela distro. Os 45 HIGH corrigíveis dependem de a Google republicar a imagem distroless. A correção é rebuildar periodicamente com o digest mais recente (ou avaliar a variante Debian 13), e não algo que se resolva no `requirements.txt`.
- O número de CRITICAL **corrigíveis** já era 0 na imagem ruim (os 16 CRITICAL dela não tinham correção na distro). O ganho real está no tamanho, no root, no vazamento, nas 3 CVEs da aplicação e nos 114 HIGH corrigíveis a menos.

## SBOM

```
$ jq '.components | length' store-api-sbom.json
55
$ jq -r '.bomFormat + " " + .specVersion' store-api-sbom.json
CycloneDX 1.7
```

## Porta de qualidade no CI

```bash
trivy image --exit-code 1 --severity CRITICAL --ignore-unfixed --scanners vuln "$IMAGE"
```

- `--exit-code 1` falha o pipeline se encontrar algo.
- `--ignore-unfixed` só barra o que **tem correção** disponível. Barrar o que não tem conserto travaria o time sem ação possível.

Verificado localmente: `store-api:1.1` retorna `exit=0` (passa), e a `store-api:vuln` com `--severity HIGH,CRITICAL` retorna `exit=1` (barrada).

## Critérios de aceite

- [x] Redução de pelo menos 80% no tamanho: −91,4% (1,7 GB para 147 MB)
- [x] Zero CVEs CRITICAL corrigíveis no relatório depois
- [x] Processo com UID diferente de 0 (65532)
- [x] SBOM válido: `jq '.components | length'` retorna 55
