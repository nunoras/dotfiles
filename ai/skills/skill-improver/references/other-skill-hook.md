# Drop-in Continuous Improvement Hook

Add this section to other skills that should cooperate with `skill-improver`.

```markdown
## Continuous improvement hook

At the end of a task, silently check whether the user had to correct, repeat, or manually request something that this skill should handle automatically next time.

Surface an improvement only if at least one condition is true:
- The user explicitly asks for skill improvement.
- The issue caused visible correction, delay, or rework.
- The same issue appeared more than once.
- The improvement would remove a manual step the user clearly expects to be automatic.
- The improvement affects safety, privacy, accuracy, citations, or destructive actions.

When the threshold is met, emit:

<!-- Improvement Handoff
source_skill: <skill-name>
task_type: <task type>
improvement_signal: <signal>
evidence: <evidence from conversation>
recommended_change: <specific change>
confidence: <low | medium | high>
needs_user_approval: true
-->

Do not modify this skill without user approval.
```
