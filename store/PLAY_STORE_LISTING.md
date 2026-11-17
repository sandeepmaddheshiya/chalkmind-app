# Chalkmind: Google Play listing

Assets in this folder: `play_icon_512.png` (store icon), `feature_graphic_1024x500.png`.
Regenerate all icons/brand images with `python3 tool/brand/generate.py`.

## App name (title, max 30)

**Chalkmind: AI Whiteboard** (24)

## Short description (max 80)

**Smart whiteboard that solves handwritten maths, explains & annotates PDFs** (73)

Alternative to A/B test later in Play Console's store listing experiments:
- *Write it, solve it. AI whiteboard for teachers, students & homework help* (72)

## Full description (max 4000)

> Write naturally. Learn smarter. Chalkmind is the AI whiteboard for teaching, homework and revision.
>
> Write a maths problem by hand, end it with "=", and Chalkmind writes the answer next to yours, in handwriting. Simple sums are solved instantly on your device, even offline. For harder problems, ask the built-in AI tutor to solve, explain, give a hint or check your working step by step.
>
> **SOLVE HANDWRITTEN MATHS**
> • Arithmetic answered instantly on the device, written back in handwriting
> • Algebra, identities, equations and geometry diagrams with the AI solver
> • Step-by-step working you can add to the board
> • Plot graphs of equations right on the page
> • Physics and chemistry too: balance equations, units, formulas
>
> **AN AI TUTOR ON YOUR BOARD**
> • Explain anything you select, in simple words
> • "Check my work" finds the first wrong line and explains the rule
> • Hints that guide without giving the answer away
> • Practice questions, quizzes, flashcards and revision notes
> • Lesson plans and worksheets for teachers
> • Flowcharts, mind maps and concept maps you can edit
> • Snap a photo of a textbook question and get it explained
>
> **IMPORT & ANNOTATE PDFs**
> • Bring in worksheets, notes and textbook chapters
> • Write, highlight and draw on top
> • Highlight any word to see its meaning, or a passage to get it explained
> • Export your annotated pages as PDF or images
>
> **A WHITEBOARD THAT FEELS LIKE PAPER**
> • Pen, pencil, marker and highlighter with stylus palm rejection
> • Smart shapes: rough circles, boxes and arrows snap into neat ones
> • Partial eraser, select, move, copy and undo
> • Page mode that fits your screen, or an infinite canvas; ruled, grid and dark boards
>
> **MADE FOR CLASSROOMS**
> • Teachers: explain live, prepare lessons, present on a classroom TV or projector by casting your tablet
> • Works on Android tablets, phones and smart-classroom touchscreen panels with Google Play
> • Students: solve homework, take notes, revise
> • Boards are saved automatically on your device
>
> **FREE TO START**
> Writing, PDFs, shapes and on-device sums are free, with daily AI answers included. Chalkmind Plus gives up to 100 AI answers a day, with a 7-day free trial.
>
> Privacy: no ads and no tracking. Your boards stay on your device. AI features send only what you choose (a selection, page or photo) to answer you; nothing is sent unless you use an AI feature.

## Contact & policy links (Play Console)

- Website: https://chalkmind.tech
- Privacy policy (required): https://chalkmind.tech/privacy
- Support email: support@chalkmind.tech
- App ID: `tech.chalkmind.app` (permanent after first upload)

## Category & tags

- Category: **Education**
- Tags (choose up to 5 in Play Console): Education, Productivity, Note taking, Math, Teaching tools

## Screenshot plan (phone + 7"/10" tablet)

Use real app screens; put a 4–6 word caption on each (captions are what people read):

1. "Write it. Solve it." (handwritten equation + answer in handwriting)
2. "Your AI tutor, on the board" (AI panel explaining a selection)
3. "Check my work, step by step" (Check my work result)
4. "Highlight a word, get its meaning" (PDF with look-up card)
5. "Mind maps & flowcharts in seconds" (generated diagram)
6. "Smart shapes and graphs" (snapped shapes + plotted graph)
7. "Built for teachers and students" (tutorial/clean board)

## Keyword notes

The title and short description carry the primary terms (whiteboard, AI, solve, maths, handwritten, PDF, annotate, explain); Play indexes the full description too, so feature terms are written naturally there (homework, worksheets, flashcards, quiz, mind map, flowchart, graph). Avoid keyword stuffing: Play penalises it. After launch, use Play Console → *Statistics → Store listing acquisition → Search terms* to see the real queries bringing installs, and adjust the short description with store listing experiments.

## App content declarations (Play Console → Policy → App content)

These match what the app and `chalkmind-server` actually do (see https://chalkmind.tech/privacy.html).

**Data safety**

- Data is collected: **Yes**. Shared with third parties: **No**. This holds because the AI provider processes requests on our behalf as a service provider, and Google Play processes payments.
- Encrypted in transit: **Yes** (HTTPS only).
- Users can request deletion: **Yes**. In-app: Account → Delete account. Web: `https://chalkmind.tech/privacy.html#delete-account`.

| Data type | Collected | Why | Optional? |
|---|---|---|---|
| Personal info → Email address, Name | Yes | Account management | Optional (only for AI features) |
| Personal info → User IDs (Google account ID) | Yes | Account management | Optional |
| Photos and videos → Photos (board images / attached photos sent for AI answers) | Yes, processed ephemerally, not stored | App functionality | Optional |
| App activity → Other user-generated content (AI questions, reported answers, feedback) | Yes | App functionality, Developer communications | Optional |
| App activity → App interactions (AI request counts per day) | Yes | App functionality (plan limits), Fraud prevention | Optional |
| App info and performance → Diagnostics (device model, Android version, recognition language; sent by Google ML Kit for on-device handwriting recognition) | Yes | Analytics | Required (collected automatically) |
| Financial info → Purchase history (subscription status from Google Play) | Yes | App functionality | Optional |

No location, contacts, device IDs or advertising IDs are collected. There are no ads SDKs; the only analytics are Google ML Kit's diagnostics listed above (see https://developers.google.com/ml-kit/android-data-disclosure).

**Other declarations**

- **Ads:** No.
- **Account deletion URL:** `https://chalkmind.tech/privacy.html#delete-account`.
- **Login credentials for review:** AI features need Google sign-in. Give reviewers a test Google account, or note that they can sign in with any Google account.
- **AI-generated content:** Yes. Users can report answers with the flag button (they appear in Admin → Reports).
- **Target audience:** 13+ (students and teachers). If you target under-13s, the Families policy applies and you must review the AI and sign-in flows against it first.

**Subscription:** product `chalkmind_plus`, with base plans `monthly` (₹249) and `annual` (₹1,999; the first `yearly` plan was set up as monthly by mistake and is deactivated). Each has a `trial-7d` 7-day free-trial offer for new customers. Plus allows 100 AI answers a day. The step-by-step setup is in `chalkmind-server/README.md`.
