import type { ReactNode } from 'react'

export function CadastroPageHeader({ title, description, children }: {
  title: string
  description: string
  children?: ReactNode
}) {
  return (
    <header className="mb-6 max-w-3xl">
      <h1 className="text-3xl font-semibold tracking-tight">{title}</h1>
      <p className="mt-2 leading-7 text-muted-foreground">{description}</p>
      {children}
    </header>
  )
}
