# Arnés de subagentes para MyFit — Diseño

Fecha: 2026-10-25
Estado: aprobada en conversación, pendiente de revisión escrita
Inspiración: [betta-tech/ejemplo-harness-subagentes](https://github.com/betta-tech/ejemplo-harness-subagentes) (patrón Líder–Trabajador–Revisor, estado en disco, verificación ejecutable)

## 1. Propósito

Dotar a MyFit de un arnés de trabajo para agentes de IA que permita desarrollar
features de forma autónoma, auditable y verificable:

- **El repo es el sistema**: las reglas, el backlog y el progreso viven en disco,
  versionados, no en el chat.
- **Orquestación multi-agente**: un leader que no edita código, un spec-writer,
  un implementer y un reviewer con responsabilidades separadas (nadie se
  autoaprueba).
- **Verificación ejecutable**: `init.sh` corre los tests reales; no nos fiamos
  de lo que un agente declara.
- **Anti teléfono-descompuesto**: los subagentes escriben sus resultados en
  `progress/` y por chat solo circulan referencias ligeras.

Las definiciones de agente usan el **formato nativo de Kimi Code** (Markdown con
frontmatter YAML en `.agents/agents/`, descubiertas automáticamente a nivel de
proyecto).

## 2. Estructura de archivos

```
.agents/agents/
├── leader.md         # orquestador — no edita código de la app
├── spec-writer.md    # redacta specs
├── implementer.md    # código + tests
└── reviewer.md       # revisión read-only
AGENTS.md             # mapa del repo con divulgación progresiva (hoy vacío)
CHECKPOINTS.md        # criterios ejecutables de "terminado"
feature_list.json     # backlog vivo: máximo 1 feature "in_progress"
init.sh               # verificación: xcodegen + tests iOS + pytest backend
progress/
├── current.md        # plan vivo de la sesión
└── history.md        # bitácora append-only
docs/
├── architecture.md   # app SwiftUI/SwiftData + backend FastAPI + Tailscale
├── conventions.md    # Swift 6, Swift Testing, estructura por features
└── verification.md   # comandos exactos de build/test
```

Todo se commitea excepto lo ya ignorado. Ajuste necesario de `.gitignore`:
pasar de ignorar todo `.agents/` a ignorar solo `.agents/skills/` (contenido de
terceros sin licencia), de modo que `.agents/agents/` viaje con el repo.

## 3. Agentes

Formato común: Markdown con frontmatter nativo de Kimi Code
(`name`, `description`, `whenToUse`, `tools`, `subagents` donde aplique).
El cuerpo es el system prompt. Todos terminan con la instrucción de que su
mensaje final sea el resultado completo y autocontenido para el llamante
(convención de handoff de Kimi Code).

### 3.1 leader

- **Rol**: orquesta el ciclo feature a feature. No edita código de la app.
- **Flujo**: lee `feature_list.json` → anuncia plan en `progress/current.md` →
  despacha `spec-writer` (si la feature no tiene spec) → `implementer` →
  `reviewer` → si el veredicto es CHANGES, vuelve al implementer con el informe →
  al cerrar, añade resumen a `progress/history.md`.
- **Reglas**: por chat solo referencias (`done -> progress/impl_<feature>.md`),
  nunca código ni diffs. Como máximo una feature `in_progress`.
- **Tools**: lectura y búsqueda, `Write`/`Edit` (solo para `progress/` y
  `feature_list.json`, por instrucción de prompt), `Agent`. Sin `Bash`.
- **subagents**: `spec-writer`, `implementer`, `reviewer`.

### 3.2 spec-writer

- **Rol**: convierte una feature del backlog en spec escrita.
- **Salida**: `docs/superpowers/specs/YYYY-MM-DD-<tema>-design.md`, misma
  convención que las specs ya existentes del proyecto. Puede leer todo el código
  para fundamentar la spec; solo escribe en `docs/superpowers/specs/`.
- **Handoff**: devuelve únicamente `spec -> docs/superpowers/specs/<archivo>`.
- **Tools**: `Read`, `Grep`, `Glob`, `Write`. Sin `Bash`, sin `Edit` fuera de specs.

### 3.3 implementer

- **Rol**: implementa UNA feature con spec aprobada.
- **Obligaciones**: corre los tests reales (`xcodebuild test` en simulador para
  la app, `pytest` para el backend); escribe `progress/impl_<feature>.md` con
  archivos tocados y salida de los tests; mueve la feature a `done` en
  `feature_list.json` solo con tests verdes.
- **Calidad**: usa como referencia los skills de proyecto `swiftui-pro`,
  `swiftdata-pro`, `swift-concurrency-pro` y `swift-testing-pro`
  (`.agents/skills/`).
- **Handoff**: `done -> progress/impl_<feature>.md`.
- **Tools**: completas (incluye `Bash` para builds/tests).

### 3.4 reviewer

- **Rol**: revisión independiente. Read-only sobre el código de la app.
- **Checklist**: spec (¿se cumple lo prometido?), `CHECKPOINTS.md`,
  `docs/conventions.md`, y los 4 skills twostraws como baremo de calidad.
  Puede re-correr tests para verificar las afirmaciones del implementer.
- **Salida**: `progress/review_<feature>.md` con veredicto `APPROVED` o
  `CHANGES` (lista numerada de cambios exigidos, con `archivo:línea`).
- **Handoff**: `approved|changes -> progress/review_<feature>.md`.
- **Tools**: `Read`, `Grep`, `Glob`, `Bash` (solo tests/build), `Agent` no.

## 4. Documentos del arnés

- **AGENTS.md**: mapa del repo con divulgación progresiva — estructura,
  comandos esenciales, y punteros a `docs/` para el detalle. Reemplaza el
  archivo vacío actual.
- **CHECKPOINTS.md**: criterios de "estado final correcto": `init.sh` verde,
  tests iOS y backend pasando, feature marcada `done` solo con evidencia en
  `progress/`, credenciales nunca en git ni en chat.
- **docs/architecture.md**: visión real de MyFit — app iOS 17+ SwiftUI +
  SwiftData + Swift 6 (XcodeGen), backend FastAPI en el Mac del usuario
  accesible vía Tailscale (`100.77.65.26:8000`), integraciones Speediance y
  Cookidoo, keychain para la API key.
- **docs/conventions.md**: Swift 6 strict concurrency, Swift Testing (no
  XCTest nuevo), estructura por features (`Models/`, `Services/`, `Views/`),
  backend con routers por servicio y settings vía `.env` sin hacer `source`.
- **docs/verification.md**: comandos exactos — `xcodegen generate`,
  `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17'`,
  `cd backend && .venv/bin/python -m pytest -v`, health check del backend.

## 5. Backlog y estado

- **feature_list.json**: array de `{id, title, status, spec}` con
  `status ∈ {pending, in_progress, done}`. Regla dura: máximo un `in_progress`;
  `init.sh` lo valida y falla en caso contrario. Contenido inicial:
  1. `e2e-cookidoo` — verificación E2E con cuenta real (T10 del plan Cookidoo).
  2. `backend-autostart` — auto-arranque del backend con launchd.
  3. `speediance-fase-2` — análisis de progresión formal.
  4. `sdd-minors` — minors diferidos de los ledgers SDD.
- **progress/current.md**: plan vivo de la sesión activa (lo reescribe el leader).
- **progress/history.md**: bitácora append-only, un resumen por sesión cerrada.

## 6. init.sh

Script ejecutable que termina verde solo si:

1. `feature_list.json` es JSON válido y tiene ≤ 1 feature `in_progress`.
2. `xcodegen generate` corre sin error.
3. `xcodebuild test -scheme MyFit -destination 'platform=iOS Simulator,name=iPhone 17'`
   pasa.
4. `cd backend && .venv/bin/python -m pytest` pasa.

Sale con código no nulo y mensaje claro en el primer paso que falle.

## 7. Integración con el flujo existente

- Specs en `docs/superpowers/specs/` y planes en `docs/superpowers/plans/`
  siguen exactamente como hasta ahora — el spec-writer produce los mismos
  artefactos que hoy produce brainstorming + writing-plans.
- `progress/` complementa (no duplica) los ledgers de `.superpowers/sdd/`:
  el ledger SDD documenta la ejecución de un plan concreto; `progress/`
  registra el ciclo leader→implementer→reviewer por feature.
- El arnés no cambia código de la app ni del backend: es tooling del repo.

## 8. Criterios de aceptación

1. `./init.sh` termina verde en `master`.
2. Las cuatro definiciones de agente son descubiertas por Kimi Code
   (visibles al invocar el tool `Agent` en una sesión del proyecto).
3. `git status` muestra `.agents/agents/` trackeado y `.agents/skills/` ignorado.
4. Un recorrido completo de prueba: leader toma una feature `pending`,
   pasa por spec → implementación → revisión, y quedan los tres informes en
   `progress/` más la feature en `done`.
