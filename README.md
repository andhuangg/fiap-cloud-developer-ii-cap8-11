# Cloud Developer II: exercícios dos capítulos 8, 9, 10 e 11

Aluno: Anderson Huang (GitHub `andhuangg`)

Ambiente: minikube (perfil `cp-bara`, Kubernetes v1.33.1, driver Docker, Apple Silicon), Argo CD v2.13.9.

Cada pasta de exercício tem os manifestos/scripts pedidos, as saídas reais dos comandos (com horário) e um relatório (`RESULTADO.md`, `ANALISE.md`, `DEPURACAO.md`, `EVIDENCIAS.md`, `RELATORIO.md` ou `MATRIZ.md`) com os critérios de aceite conferidos.

## Repositórios do capítulo 11

- Config repo (GitOps): https://github.com/andhuangg/fiap-store-config
- App repo + CI: https://github.com/andhuangg/fiap-store-api
- Imagens: `ghcr.io/andhuangg/fiap-store-api` (1.0, 1.1 e 6, multi-arch, assinadas com Cosign)

Cópia local dos dois repositórios em `cap11/repos/`.

## Índice

| Exercício | Tema | Relatório |
|---|---|---|
| 8.1 | Job paralelo e Job Indexed | `cap08/ex8.1/RESULTADO.md` |
| 8.2 | CronJob Allow x Forbid, Secret por env x volume | `cap08/ex8.2/ANALISE.md` |
| 8.3 | Depuração: Job, Secret, Service sem endpoints | `cap08/ex8.3/DEPURACAO.md` |
| 8.4 | Fila com escala a zero (KEDA) + comparação | `cap08/ex8.4/RESULTADO.md`, `COMPARACAO.md` |
| 9.1 | ServiceAccount somente leitura | `cap09/ex9.1/EVIDENCIAS.md` |
| 9.2 | Usuário por certificado e kubeconfig | `cap09/ex9.2/RELATORIO.md` |
| 9.3 | Depuração de quatro Forbidden | `cap09/ex9.3/DEPURACAO.md` |
| 9.4 | Modelo RBAC de 4 perfis + matriz | `cap09/ex9.4/MATRIZ.md` |
| 10.1 | securityContext e PSA | `cap10/ex10.1/RESULTADO.md` |
| 10.2 | Trivy, distroless e SBOM | `cap10/ex10.2/RESULTADO.md` |
| 10.3 | Rolling update sem perder conexões | `cap10/ex10.3/RESULTADO.md` |
| 10.4 | Checklist de produção + Kustomize | `cap10/ex10.4/RESULTADO.md`, `CHECKLIST.md` |
| 11.1 | Argo CD e primeira Application | `cap11/ex11.1/RESULTADO.md` |
| 11.2 | Promoção dev para prod por PR | `cap11/ex11.2/RESULTADO.md` |
| 11.3 | Depuração GitOps (drift, Degraded, Sealed Secrets) | `cap11/ex11.3/RELATORIO.md` |
| 11.4 | App-of-Apps + CI que abre PR + Knative | `cap11/ex11.4/RESULTADO.md` |

`app/` contém o código-fonte da `store-api` usado nos capítulos 8 a 10.

## Arquivos omitidos neste repositório

Por boa prática, as chaves privadas (`*.key`) e os kubeconfigs dos usuários de teste do capítulo 9 (ex. 9.2 e 9.4), além dos arquivos `.env` de demonstração do ex. 10.2, não foram versionados. Eles estão no zip entregue no Teams.
