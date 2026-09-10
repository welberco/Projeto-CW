import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { NoPermissionPage } from '@/app/pages/no-permission-page'

describe('NoPermissionPage', () => {
  it('renders a safe state without implying client-side authorization', () => {
    render(<NoPermissionPage />)

    expect(screen.getByRole('heading', { name: 'Sem permissão' })).toBeVisible()
    expect(screen.getByText(/interface não concede autorização/)).toBeVisible()
  })
})
