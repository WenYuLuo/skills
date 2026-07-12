---
name: editable-arch-ppt
description: Create editable PowerPoint architecture diagrams from technical docs, repo analysis, or user sketches. Use for system architecture, deployment, K8s/runtime, control-plane/data-plane, agent-runtime, sandbox, or component-flow diagrams — single-slide OR multi-slide decks — where output must be native PPT shapes/text/connectors rather than a flat image.
---

# Editable Architecture PPT

Use this skill to turn technical material into **editable architecture diagrams**. Supports both single-slide diagrams and multi-slide narrative decks. Optimized for system/runtime/deployment diagrams, not generic marketing decks.

## Core rule

Do **not** draw first. First build the architecture semantic model, then a layout blueprint, then render PPT, then QA.

```text
semantic model -> layout blueprint -> native PPT rendering -> structural QA
```

## Output contract

Produce a `.pptx` file with:

- One architecture slide unless the user asks otherwise.
- Native PowerPoint shapes for modules/layers.
- Native PowerPoint text boxes for labels.
- Native PowerPoint elbow connectors (`bentConnector*`) for main paths.
- Arrowheads on directed flows.
- A legend mapping colors/line styles to semantics.
- No full-slide screenshots or bitmap-only architecture diagrams.

Final response must include:

```text
Output path
What the diagram represents
Validation evidence: slide count, editable object count, bentConnector count, plain line count, arrowhead count
Remaining risks / manual polish notes
```

## Workflow

### 1. Ground and separate semantics

Extract only facts supported by the user-provided material, local repo, docs, or explicit assumptions. Separate these categories before layout:

- **Layers / boundaries**: cloud, Kubernetes cluster, namespace, node, pod, sandbox, process.
- **Components**: services, controllers, daemons, sidecars, stores, external clients.
- **Data flow**: user/business request path, request/response, streaming path.
- **Control flow**: reconcile, create, resume, routing resolution, scheduler/API calls.
- **Runtime/internal flow**: container runtime, sandbox, checkpoint/restore, local socket/gRPC.
- **Config/declarative resources**: CRDs, templates, manifests, specs. Do not place these on the data path unless they really handle requests.
- **State/storage**: Redis/ValKey, object storage, DB, event logs, snapshots.

If a component name is code-grounded, preserve the exact name (`ateom-gvisor`, not `ate-gvisor`). Mark uncertain expansions as inference.

### 2. Build a layout blueprint before PPT

Create a compact blueprint in your reasoning or a temporary JSON spec. Prefer this lane structure for cloud/runtime diagrams:

```text
left:    user/client/CLI
upper:   ingress + application control plane
middle:  platform/substrate/K8s control plane
lower:   worker node / pod / sandbox / runtime
right:   stores, K8s API, legend
bottom:  key boundary statement / takeaway
```

Routing rules:

- Reserve empty corridors for lines before placing boxes.
- Reserve **gutter space** around every meaningful module: keep routed lines at least `0.18in` away from component borders except at the final source/target contact point.
- Final arrow segments must enter the target box **perpendicular** to the contacted edge: horizontal into left/right edges, vertical into top/bottom edges. Do not use a line that lies parallel to, or flat along, a box edge and then pretend it targets that box.
- Arrowheads must visibly touch the target box border or an explicit small port/pin dot placed just outside the border. Floating arrowheads that stop short of a box are invalid.
- Data flow usually goes outer/bottom corridor, not through control-plane modules.
- Control flow can use upper/middle corridors.
- Runtime calls should be short local arrows inside a node/pod.
- Use native elbow connectors for main paths; avoid drawing main paths with plain straight lines.
- Prefer a longer route over crossing a module.
- Do not let a connector **run along** a module edge. Endpoints may touch a source/target border, but the connector body must not share the same x/y as a box side while overlapping that side.
- Watch specifically for **edge-hugging segments**: a horizontal line glued to a box's top/bottom edge, or a vertical line glued to a box's left/right edge. This is worse than a normal endpoint contact because the line visually becomes part of the box border.
- If a line exits a component, use a short perpendicular stub and then turn into a corridor with visible separation; do not turn immediately onto the component's border line.
- If a line visually hugs a box, move it to a dedicated corridor or add a small port/pin outside the box.
- Do not route a connector through the center of a component box or over its text. Use edge ports: connect to the nearest border or to a small dot just outside the border.
- For hub-and-spoke diagrams, place the hub outside the text area or use perimeter ports; avoid drawing spokes into the center of labeled boxes.
- Labels sit near the path but should not cover module names.
- If a connector would need to pass through a box, split the slide, move the box, add a side bus, or remove the arrow. Never accept a line crossing text as a tradeoff.

Recommended clearance defaults:

```text
min_connector_clearance: 0.18in
preferred_connector_clearance: 0.25-0.35in
outer_corridor_width: >= 0.35in
between_layer_corridor_width: >= 0.30in
```

When the slide is dense, reduce the number of arrows before reducing the clearance. A readable architecture diagram beats a fully connected but unreadable one.

Typography defaults for engineering-whiteboard slides:

```text
title: 15-18pt
section labels: 10-12pt
component labels: 8.5-10pt
flow labels: >= 7.5pt
body notes: 8.5-10pt
```

Do not shrink fonts to fit everything. If text needs to go below these sizes, split the slide or move explanation into a note box.

Text-fit rules:

- Component boxes contain short names only. Do not put multi-line explanations, field lists, or sentence fragments inside component boxes.
- A component label must have stable visual proportion: normally 8.5-11pt, centered, with at least `0.08in` horizontal text margin and `0.05in` vertical margin.
- Body notes and field lists need enough height for their line count. If a note touches or exits its box, enlarge the note, shorten the copy, or split the slide. Do not rely on PowerPoint auto-fit making text tiny.
- Footer/source notes must live in their own reserved band and must not overlap the main content panel.
- Before rendering, estimate text fit from longest lines and line count; after rendering, visually inspect dense text slides at 100% zoom.

Readable layout defaults:

```text
top title band: 0.85-1.0in reserved
panel title to first component: >= 0.35in
component vertical gap: >= 0.28in
component horizontal gap: >= 0.35in
note box body: prefer 2-4 bullets, not paragraphs inside diagram boxes
```

Component boxes should contain short names only. Put explanations, tradeoffs, and "why this matters" into a separate note box. If a label overlaps or visually touches another box, the layout is wrong; do not solve it by shrinking fonts.

### 3. Use the bundled renderer when useful

For reliable native PPT output, prefer the bundled renderer:

```bash
python /home/lzc/workspace/skills/editable-arch-ppt/scripts/render_arch_ppt.py \
  --spec /path/to/spec.json \
  --out /path/to/output.pptx
```

Lint the spec for routing clearance before or after rendering:

```bash
python /home/lzc/workspace/skills/editable-arch-ppt/scripts/render_arch_ppt.py \
  --lint-spec /path/to/spec.json \
  --clearance 0.18
```

Generate an example spec:

```bash
python /home/lzc/workspace/skills/editable-arch-ppt/scripts/render_arch_ppt.py --write-example /tmp/arch-spec.example.json
```

The renderer expects slide coordinates in inches on a 13.333 x 7.5 canvas. It creates native PPT objects and injects arrowheads into DrawingML.

Read `references/notebooklm-arch-style.md` only when you need the detailed default style vocabulary.

### 4. QA before reporting completion

Run a structural check after saving. The renderer prints one, or inspect manually:

```bash
python - <<'PY'
from pptx import Presentation
import zipfile, sys
p=sys.argv[1]
prs=Presentation(p)
with zipfile.ZipFile(p) as z:
    xml='\n'.join(z.read(n).decode(errors='ignore') for n in z.namelist() if n.startswith('ppt/slides/slide') and n.endswith('.xml'))
print('slides=', len(prs.slides), 'objects=', sum(len(s.shapes) for s in prs.slides))
print('bentConnector=', xml.count('bentConnector'), 'plain_line=', xml.count('prst="line"'))
print('arrowheads=', xml.count('<a:tailEnd') + xml.count('<a:headEnd'))
PY /path/to/output.pptx
```

Minimum pass bar:

- `slides >= 1`
- `objects > 20` for a non-trivial architecture slide
- `bentConnector > 0` when there are flows
- `arrowheads > 0` when there are directed flows
- `plain_line == 0` for main flow connectors; if nonzero, explain why or regenerate
- spec lint should report no connector segments crossing module rectangles, no non-terminal line corridors within the clearance gutter, no text overflow risks, no floating arrow endpoints, and no arrow endpoint entering a box from a parallel segment. If there are warnings, reroute, resize, shorten copy, split slides, or simplify arrows before reporting completion.

Also inspect logically:

- No orphan/hanging flow lines.
- No connector body visually hugs the border of a box. Endpoint contact is OK; a long horizontal/vertical segment lying on a box edge is not OK.
- Arrowheads visibly terminate on the intended box border or explicit port dot, and the final segment is perpendicular to that border.
- No connector crosses a component box or text area, even if the line is behind the text.
- No text leaves its textbox or appears tiny relative to peer labels. Component labels, note bodies, and footers must look intentionally sized.
- Data/control/runtime/config flows are not conflated.
- Config/CRD boxes are not in the business request path unless true.
- Major arrows have labels and readable direction.
- Legend matches actual line styles.

## Default visual grammar

Use this vocabulary unless the user specifies a brand/style:

- Gray background: infrastructure/cloud boundary.
- Green areas: Kubernetes cluster, worker node, pod.
- Blue areas: application runtime layer / AX-like layer.
- Yellow areas: substrate/platform control plane.
- Light blue dashed area: sandbox/runtime isolation boundary.
- Orange boxes/lines: runtime helper or local container-runtime calls.
- Purple thick solid arrows: business/data path.
- Blue dashed arrows: control path.
- Gray/light-blue small boxes: declarative config/CRDs/templates.

## Style profile: engineering-whiteboard

Use this when the user references `sandbox.pptx`, engineering design review slides, internal architecture sketches, or asks for a less "infographic" look.

Principles:

- White background first; avoid large decorative color blocks.
- Use thin gray/black borders and plain rectangular boxes for most components.
- Highlight only the current slide's focus with one or two muted colors.
- Prefer containment, alignment, and layering over explicit arrows.
- Draw only key cross-boundary calls or dependencies; do not connect every component.
- Put detailed reasoning in a right-side explanation box instead of arrow labels and legends.
- Use step numbers near important calls instead of a large color legend.
- If a flow needs many bends, redesign the layout rather than adding more connectors.
- Keep arrows short and purposeful; long arrows should represent a true end-to-end path.
- Preserve detail where the user's goal is an architecture/deployment view. In that case, draw the real component topology, but keep it whiteboard-style: thin boxes, sparse colors, and only key request/control/runtime paths.

Hard-won engineering-whiteboard rules:

- **Readable typography beats density.** Never go tiny to preserve all text; shorten labels or move text to notes.
- **Panel headers need breathing room.** A section label must not sit on top of its child boxes.
- **No line may pass through a component box, even if it does not hit the text.** If it would, move the component, use a perimeter bus, or remove the line.
- **For hub diagrams, use side buses.** Put objects in left/right columns and connect their nearest edges to a vertical bus, then connect the bus to the hub. Do not draw spokes through neighboring boxes.
- **For deployment views, keep topology detail.** Do not simplify a deployment architecture into generic step cards; retain real components and use a few numbered key paths.
- **Use notes to explain; use lines to prove a path.** If a line is not proving a key path, prefer containment/alignment instead.

In this style, do not force the default purple/blue/orange flow grammar unless the slide needs it. Most lines can be thin black/gray, with red/blue used only for the key path under discussion.

## Supported diagram types in v1

1. `layered-runtime-architecture`: client -> ingress -> control plane -> worker node -> sandbox.
2. `k8s-control-data-plane`: K8s API/controllers/CRDs + node daemon + pod runtime.
3. `agent-runtime-routing`: conversation/request -> router/resolver -> actor instance -> stream response.

For other diagram types, still follow the semantic-model -> blueprint -> render -> QA workflow, but mention any style drift in final notes.

---

## Multi-slide deck pattern

When the user asks for a **narrative deck** (problem + abstractions + deployment + use cases + comparison + summary), write a single Python script that builds all slides in one `Presentation` object. Do NOT produce one PPT per slide and merge — build them all at once.

### Script structure

```python
prs = Presentation()
prs.slide_width  = Inches(13.333)
prs.slide_height = Inches(7.5)
blank = prs.slide_layouts[6]   # blank layout

def slide_01_positioning(prs): ...
def slide_02_problem(prs): ...
def slide_03_abstractions(prs): ...
def slide_04_deployment(prs): ...   # main arch diagram — bentConnectors
def slide_05_uc_xxx(prs): ...       # use case slides
...

for builder in [slide_01_..., ...]:
    builder(prs)

prs.save(out)
```

### Slide type mix

| Slide type | Connectors needed | Notes |
|---|---|---|
| Text / positioning | None | Just boxes + textboxes |
| Architecture diagram | Many bentConnectors | Apply full layout blueprint |
| Sequence / flow | Red story connectors + gray structure | See below |
| Comparison table | None | Use grid of boxes |

### Reference implementation

`/home/lzc/workspace/code/agentruntime/gen_ax_v8.py` — 10-slide AX Agent Runtime deck. Contains reusable helper functions: `box()`, `tb()`, `flow()`, `connector()`, `label()`, `add_arrowhead()`, `set_text()`, `blank_slide()`, `slide_title()`, `note_box()`. Copy and adapt these helpers rather than rewriting from scratch.

---

## Engineering-whiteboard style: sandbox.pptx rules

These rules were distilled from hand-drawn engineering review slides. Apply when the user references `sandbox.pptx` or asks for an internal whiteboard feel.

### Component box typography

- **Name only inside the box, 10–11 pt bold.** Never put descriptions, sub-bullets, or secondary info inside component boxes. Move descriptions to a side note box or a step-reference box below the diagram.
- Panel/section labels: 8.5–9.5 pt, placed at the top-left of the containing panel, not inside a component box.
- Annotation labels (flow labels, port labels): 7–8.5 pt, outside the boxes.

### Story flows vs. structural background

Use two visually distinct layers for use-case / sequence slides:

| Layer | Color | Width | Dash | Usage |
|---|---|---|---|---|
| Story steps | `#DC2626` (story_red) | 2.0–2.5 pt | solid | Numbered ① ② ③ arrows that tell the use-case story |
| Structural background | `#9E9E9E` or `#1976D2` dashed | 0.9–1.2 pt | solid or dashed | Static topology, state writes, config flows |

Place step numbers in the flow label text (`① create SB`, `② connect tunnel`), not as separate shapes.

### Data-path thickness

- Main business data path (request/response): **2.5 pt** purple or red.
- Control path (create/resume/reconcile): **1.2–1.5 pt** blue dashed.
- Runtime calls (atelet → ateom, UDS): **1.2–1.4 pt** orange solid.
- Background / config flows: **0.9–1.0 pt** gray.

Thickness alone should make the primary path immediately visible without needing to read labels.

### Palette additions

```python
PAL["story_red"] = "DC2626"   # numbered step flows in use-case slides
```

---

## Supported diagram types (v2)

1. `layered-runtime-architecture`: client → ingress → control plane → worker node → sandbox.
2. `k8s-control-data-plane`: K8s API/controllers/CRDs + node daemon + pod runtime.
3. `agent-runtime-routing`: conversation/request → router/resolver → actor instance → stream response.
4. `multi-slide-narrative`: problem + abstractions + deployment + use cases + comparison + summary — use the multi-slide deck pattern above.
5. `use-case-sequence`: numbered red story flows + gray structural background + step reference box.

For other diagram types, still follow the semantic-model → blueprint → render → QA workflow, but mention any style drift in final notes.
