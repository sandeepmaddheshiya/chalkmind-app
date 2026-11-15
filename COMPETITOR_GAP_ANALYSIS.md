# Competitor Gap Analysis

_Researched 2026-11-15 via web search. Where a claim comes only from third-party reviews or older material it is marked **(secondary)** or **(dated)**; verify against vendor docs before using it externally. No pricing is stated here except where a source states it, because pricing in the results conflicted._

## 1. What competitors offer (sourced)

| Product | Relevant capabilities found | Sources |
|---|---|---|
| **Miro** | AI agents / "Sidekicks" and AI Workflows on the canvas (2026); generate related stickies, summarize notes, generate ideas from a prompt; MCP server (beta) and AI Slides. Education use positioned around collaborative group work. Education/paid AI data excluded from model improvement. | [The Next Web](https://thenextweb.com/news/miro-ai-workspace-team-collaboration), [Gend: Feb 2026 updates](https://www.gend.co/blog/miro-february-2026-updates), [Inria AI4T](https://inrialearninglab.github.io/ai4t//2.5-teachers-usages/tools/uni_hs-miro-ai.html) (secondary), [Linktly review](https://www.linktly.com/productivity-software/miro-review/) (secondary) |
| **FigJam** | AI "Generate" boards/flowcharts/mind maps from a prompt; Sort stickies by theme; Summarize stickies (result not editable, only copyable); Jambot widget. AI on paid plans; powered by OpenAI. | [Figma Help: Use AI tools in FigJam](https://help.figma.com/hc/en-us/articles/16822138920343), [TechCrunch 2023](https://techcrunch.com/2023/11/07/figma-sweetens-figjam-whiteboard-tool-with-new-ai-features/) (dated) |
| **Microsoft Whiteboard** | Ink beautification, Ink Grab (photo → ink), Copilot suggestions incl. templates, ink-to-shape, ink replay; export to OneNote Class Notebooks; free for education via M365 A1. Step-by-step handwritten math solving and equation graphing live in **OneNote** (Ink Math Assistant), not Whiteboard. | [Thurrott](https://www.thurrott.com/cloud/office-365/192585/microsoft-whiteboard-launches-for-education-customers-with-cool-new-features) (dated), [Microsoft Learn: OneNote math](https://learn.microsoft.com/en-gb/training/modules/independent-learning-math-tools-onenote/personalize-learning-process), [Microsoft 365 blog](https://www.microsoft.com/en-us/microsoft-365/blog/?p=233437) |
| **Explain Everything** | Lesson recording to "Explainer Videos" with a timeline you can edit; laser pointer (multiple styles, size), zoom and pan are recordable; collaboration with view/edit permissions; menus hidden in recordings. | [Wacom community](https://community.wacom.com/en-us/the-top-3-explain-everything-features-for-teachers/amp), [Promethean](https://learn.prometheanworld.com/articles/explain-everything-explained-everything-you-need-all-in-one-place/), [Explain Everything blog (Jun 2026)](https://explaineverything.com/blog/news/a-school-year-full-of-explain-everything-updates/) |
| **Whiteboard.fi** | Every student gets a private board; teacher sees all boards live and can write on any; push teacher board to class; focus mode freezes student screens; download all student boards as PDF/ZIP; join by link/code/QR with no accounts; co-teachers. | [Whiteboard.fi blog](https://blog.whiteboard.fi/top-whiteboard-fi-features-for-the-physical-classroom/), [Kahoot!](https://kahoot.com/schools/whiteboard-fi/), [NIE Singapore](https://learn.nie.edu.sg/etoolsNIE/info.aspx?id=298) (dated), [PPLI tutorial 2020](https://ppli.ie/wp-content/uploads/2020/08/WHITEBOARD.FI-Tutorial.pdf) (dated) |
| **OpenBoard** | Free GPLv3 desktop whiteboard for schools (Windows/macOS/Linux); interactive whiteboards, pen tablets, dual-screen; resource library and web widgets. Reported: no iOS/Android version, no real-time collaborative writing. | [openboard.ch](https://openboard.ch/en), [It's FOSS](https://itsfoss.com/openboard/), [LinuxLinks](https://www.linuxlinks.com/openboard-interactive-whiteboard-schools-universities) |
| **Excalidraw** | AI text-to-diagram producing editable diagrams; real-time collaboration with shareable and read-only links; Excalidraw+ paid tier. | [Geeky Gadgets](https://www.geeky-gadgets.com/ai-diagram-creation-tool-excalidraw/) (secondary), [HKMU OE tools](https://www.hkmu.edu.hk/oetools/excalidraw) (secondary) |
| **tldraw** | Open-source canvas SDK aimed at developers; minimal native AI per one comparison. | [MockFlow comparison](https://mockflow.com/blog/excalidraw-alternatives) (secondary), [OpenAlternative](https://openalternative.co/alternatives/tldraw) (secondary) |
| **Khanmigo** | Socratic tutor that guides with questions instead of giving answers and flags common mistakes; teacher tools for lesson plans (objectives, hooks, exit tickets), rubrics, class snapshots. Teacher tools stated free on official page; student classroom access via schools/districts. | [Khan Academy blog: Khanmigo features](https://blog.khanacademy.org/khanmigo-features/), [khanmigo.ai/teach](https://khanmigo.ai/teach), [AVID Open Access](https://avidopenaccess.org/resource/ed-tip-khanmigo-a-personal-tutor-and-teaching-assistant/) |
| **Photomath / Mathway / GeoGebra** | Photomath: scan → verify recognized input → step-by-step (free-tier step availability disputed across sources). Mathway: typed/photo/voice input, broad subjects. GeoGebra: dynamic geometry and graphing for exploration. No GeoGebra notes/whiteboard details found. | [Apple App Store story](https://apps.apple.com/us/story/id1425823664), [comparison page](https://gt-math-online.pages.dev/compare/math-photos-vs-photomath-vs-mathway-vs-symbolab) (secondary), [AlternativeTo: GeoGebra](https://alternativeto.net/software/geogebra-classic) (secondary) |

## 2. Where Chalkwise is already stronger

1. **Math inside the whiteboard ink flow.** Write an equation ending in `=` and Chalkwise solves it locally with zero network latency and can write the answer back *in handwriting style* along the writer's slant. Microsoft puts this in OneNote rather than Whiteboard; Photomath/Mathway are separate camera apps. General whiteboards (Miro, FigJam, Excalidraw) have no equivalent in the sources found.
2. **Interactive graphs as board objects** (pan/zoom inside the plot, key points) next to the ink — closer to GeoGebra than to general whiteboards.
3. **Pedagogical AI on the board itself** (new): *Check my work* is prompted to find the **first incorrect step** and explain it; *Hint* withholds the final answer. This mirrors Khanmigo's Socratic approach but applied to what is actually written on the board.
4. **AI diagrams are editable native objects** (shapes, arrows, text) — on par with Excalidraw/FigJam generation, and unlike FigJam's non-editable summaries.
5. **Works offline / no account** for everything except AI; boards stay on device. Comparable to OpenBoard, but with touch/stylus and mobile support (OpenBoard reportedly lacks iOS/Android).

## 3. Where competitors are stronger (gaps)

| Gap | Who does it | Value for education | Effort |
|---|---|---|---|
| Real-time collaboration, sharing links, permissions | Miro, FigJam, Excalidraw, Explain Everything | Very high | **High** — needs backend |
| Teacher sees every student board live, push board to class, focus mode, no-account join | Whiteboard.fi | **Very high** for live lessons | High (same backend) |
| Lesson recording / replay with timeline | Explain Everything; MS Whiteboard ink replay | High (flipped classroom, absent students) | Medium — strokes already carry timestamps |
| Photo → ink / place images on board | MS Whiteboard Ink Grab | High (textbook questions on board) | Medium — add `ImageObject` |
| Laser pointer styles / trail | Explain Everything | Medium | Low |
| Export to LMS / class notebooks | MS Whiteboard → OneNote | Medium | Medium |
| Templates library, resource library | Miro, OpenBoard | Medium | Low–Medium |
| Admin/data-privacy controls for minors | Khanmigo (FERPA/COPPA claims), Miro edu | High for school adoption | Medium (proxy backend) |

## 4. Recommended roadmap (highest value first)

1. **Classroom sessions (backend).** Suggested architecture: a small sync service (e.g. WebSocket relay with per-board rooms) carrying the *existing* command objects (`AddElements`, `ReplaceElements`, `MoveElements`) as operations — the command layer built in this round is already the right unit for sync. Add teacher-owned rooms, join codes (Whiteboard.fi-style, no student accounts), and per-room authorization. Route AI calls through the same backend to keep API keys off student devices and enforce per-class limits.
2. **Lesson recording/replay** using stroke timestamps already stored on every point.
3. **Image objects** so uploaded textbook photos can sit on the board next to the AI explanation.
4. **Laser trail, pressure-sensitive ink, resize/rotate handles** (local, low effort, high feel).
5. **Typeset math** (LaTeX) for AI output and text objects.

## 5. Differentiation statement

> The whiteboard where math written by hand is understood, solved, graphed and explained in place — with an AI tutor that checks a student's own working step by step rather than just giving answers.
