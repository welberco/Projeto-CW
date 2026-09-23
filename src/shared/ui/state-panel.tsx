import type { ReactNode } from 'react'
import { cn } from '@/shared/lib/cn'

interface StatePanelProps {
  title: string
  description: string
  action?: ReactNode
  kind?: 'neutral' | 'error'
  live?: 'off' | 'polite' | 'assertive'
  className?: string
  headingLevel?: 1 | 2
}

export function StatePanel({
  title,
  description,
  action,
  kind = 'neutral',
  live = 'off',
  className,
  headingLevel = 1,
}: StatePanelProps) {
  const Heading = headingLevel === 1 ? 'h1' : 'h2'
  return (
    <section
      aria-live={live}
      className={cn(
        'rounded-xl border bg-card p-6 text-card-foreground shadow-sm',
        kind === 'error' && 'border-destructive/35',
        className,
      )}
      role={kind === 'error' ? 'alert' : undefined}
    >
      <Heading className="text-xl font-semibold tracking-tight">{title}</Heading>
      <p className="mt-2 max-w-2xl text-sm leading-6 text-muted-foreground">
        {description}
      </p>
      {action === undefined ? null : <div className="mt-5">{action}</div>}
    </section>
  )
}
