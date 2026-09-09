import type { ReactNode } from 'react'
import { cn } from '@/shared/lib/cn'

interface StatePanelProps {
  title: string
  description: string
  action?: ReactNode
  kind?: 'neutral' | 'error'
  live?: 'off' | 'polite' | 'assertive'
  className?: string
}

export function StatePanel({
  title,
  description,
  action,
  kind = 'neutral',
  live = 'off',
  className,
}: StatePanelProps) {
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
      <h1 className="text-xl font-semibold tracking-tight">{title}</h1>
      <p className="mt-2 max-w-2xl text-sm leading-6 text-muted-foreground">
        {description}
      </p>
      {action === undefined ? null : <div className="mt-5">{action}</div>}
    </section>
  )
}
