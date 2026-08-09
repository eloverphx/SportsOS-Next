"use client";

const sections = [
  {
    id: "attention",
    href: "#director-attention",
    label: "Attention",
    detail: "Urgent issues",
  },
  {
    id: "focus",
    href: "#director-focus",
    label: "Focus",
    detail: "Narrow games",
  },
  {
    id: "timeline",
    href: "#director-timeline",
    label: "Timeline",
    detail: "Rink schedule",
  },
  {
    id: "scheduling",
    href: "#director-scheduling",
    label: "Scheduling",
    detail: "Safe changes",
  },
] as const;

export function TournamentOperationsNavigation() {
  return (
    <nav
      className="tournamentWorkflowNav"
      aria-label="Tournament Director workflow"
      data-testid="tournament-workflow-nav"
    >
      <div className="tournamentWorkflowIntro">
        <span>Director workflow</span>
        <strong>See it → focus it → schedule it</strong>
      </div>

      <div
        className="tournamentWorkflowLinks"
        data-testid="tournament-workflow-links"
      >
        {sections.map((section, index) => (
          <a
            key={section.id}
            href={section.href}
            data-testid={`workflow-link-${section.id}`}
            aria-label={`${section.label}: ${section.detail}`}
          >
            <span className="tournamentWorkflowStep" aria-hidden="true">
              {index + 1}
            </span>
            <span>
              <strong>{section.label}</strong>
              <small>{section.detail}</small>
            </span>
          </a>
        ))}
      </div>
    </nav>
  );
}
