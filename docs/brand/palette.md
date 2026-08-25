# mobileLM — Identidade visual

Conceito: **bolha + raio** — "um modelo local que age". Dark-first, energia sem neon-cafona.

## Paleta

| Token | Hex | Uso |
|---|---|---|
| Ink 900 | `#0B1018` | fundo base |
| Ink 800 | `#131B27` | superfícies (cards) |
| Ink 700 | `#1D2838` | elevação, bolhas do chat |
| Slate 200 | `#E7ECF2` | texto primário |
| Slate 400 | `#94A3B8` | texto secundário |
| **Volt 500** | `#B9F53E` | accent primário: CTAs, foco, ícone |
| Volt 600 | `#8FD42A` | hover/pressed |
| Pulse 500 | `#8B7CFF` | accent secundário (IA/pensamento), máx. 10% da tela |
| OK / Warn / Danger | `#34D399` / `#FBBF24` / `#F87171` | semânticas |

Regras: Volt nunca em texto corrido longo (contraste); Pulse só em estados de
"modelo pensando"/gradiente sutil; modo claro usa Ink 900 invertido com os mesmos accents.

## Tipografia

- Display: **Space Grotesk** (títulos, logo)
- UI: **Inter**
- Código/tool calls: **JetBrains Mono**

## Forma

- Raio de card 24dp, botões pill 32dp.
- Ícone launcher: tile escuro raio 115/512, bolha Ink 700, raio Volt com gradiente
  `#C6F542 → #8FE83A`, faísca Pulse no canto superior direito.
- Versões: `logo.svg` (ícone), `lockup.svg` (ícone + wordmark), mono via `currentColor`.
