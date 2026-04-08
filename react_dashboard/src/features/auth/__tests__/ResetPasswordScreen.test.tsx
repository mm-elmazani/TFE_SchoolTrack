import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '../../../test/test-utils';
import ResetPasswordScreen from '../screens/ResetPasswordScreen';

vi.mock('@/api/axios', () => ({
  apiClient: { post: vi.fn() },
}));

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return {
    ...actual,
    useParams: () => ({ schoolSlug: 'dev' }),
    useSearchParams: () => [new URLSearchParams()],
  };
});

describe('ResetPasswordScreen — no token', () => {
  it('shows invalid link when no token/email', () => {
    render(<ResetPasswordScreen />);
    expect(screen.getByText('Lien invalide')).toBeInTheDocument();
    expect(screen.getByText(/reinitialisation est invalide/)).toBeInTheDocument();
  });

  it('shows link to request new reset', () => {
    render(<ResetPasswordScreen />);
    expect(screen.getByText(/nouveau lien/i)).toBeInTheDocument();
  });
});
