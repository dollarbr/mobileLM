# mobileLM — Agent Guide

Objetivo do repo: mix do **PrivateLM** (motor local Flutter) com **PocketStrike-AI**
(camada de agente). Fonte da verdade do roadmap: [`docs/PLAN.md`](docs/PLAN.md) — leia antes de qualquer tarefa.

## Estado atual

M0 concluído: apenas docs + marca. **Ainda não existe código de app.**
No M1 a codebase do PrivateLM entra neste repo — até lá, não criar scaffold Flutter à mão.

## Regras herdadas (aprendidas nas sessões anteriores)

- Base M1 = fork do PrivateLM (`../mobileLM/../privateLM` no workspace local). Não recriar
  engine, plugins nativos (`local_plugins/*`) nem escada de aceleração do zero.
- De PocketStrike portar **padrões e catálogo**, não código Kotlin inteiro:
  `[TOOL_CALL]`, lazy registry, parser tolerante. O privateLM já tem parser tolerante em
  `lib/services/tools/` — estender, não duplicar.
- Tool que escreve/envia/apaga exige **confirmação humana** na UI. Leitura pura pode ser auto.
- Agente multi-passo só atrás de toggle, com teto de iterações (modelos pequenos loopam).
- Nativo arm64-only; licenças MIT dos upstreams devem ser citadas (README/LICENSE já cobrem).

## Identidade

Spec completa em `docs/brand/palette.md`. Ícone: `docs/brand/logo.svg`.
Dark-first, accent Volt `#B9F53E`, Pulse `#8B7CFF` com parcimônia.

## Comandos (valem a partir do M1)

Idênticos ao privateLM (Flutter): `flutter pub get`, `flutter analyze --no-fatal-infos --no-fatal-warnings`,
`flutter test`, tag `<x.y.z>` dispara release de APKs split-per-abi.
