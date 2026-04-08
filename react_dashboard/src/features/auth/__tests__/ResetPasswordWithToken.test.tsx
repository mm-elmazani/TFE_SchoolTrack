import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '../../../test/test-utils';
import userEvent from '@testing-library/user-event';
import ResetPasswordScreen from '../screens/ResetPasswordScreen';
import { apiClient } from '@/api/axios';

vi.mock('@/api/axios', () => ({
  apiClient: { post: vi.fn() },
}));

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return {
    ...actual,
    useParams: () => ({ schoolSlug: 'dev' }),
    useSearchParams: () => [new URLSearchParams('token=abc123&email=test@test.be')],
  };
});

beforeEach(() => vi.clearAllMocks());

describe('ResetPasswordScreen — with token', () => {
  it('shows password form when token and email present', () => {
    render(<ResetPasswordScreen />);
    expect(screen.getAllByText('Nouveau mot de passe').length).toBeGreaterThan(0);
    expect(screen.getByLabelText('Nouveau mot de passe')).toBeInTheDocument();
    expect(screen.getByLabelText('Confirmer le mot de passe')).toBeInTheDocument();
  });

  it('shows submit button', () => {
    render(<ResetPasswordScreen />);
    expect(screen.getByRole('button', { name: /reinitialiser/i })).toBeInTheDocument();
  });

  it('shows back to login link', () => {
    render(<ResetPasswordScreen />);
    expect(screen.getByText(/Retour a la connexion/)).toBeInTheDocument();
  });

  it('shows password requirements', () => {
    render(<ResetPasswordScreen />);
    expect(screen.getByText(/Min. 8 caracteres/)).toBeInTheDocument();
  });

  it('toggles password visibility', () => {
    render(<ResetPasswordScreen />);
    const toggleBtn = screen.getByLabelText('Afficher');
    fireEvent.click(toggleBtn);
    expect(screen.getByLabelText('Masquer')).toBeInTheDocument();
  });

  it('shows success state after successful reset', async () => {
    const user = userEvent.setup();
    vi.mocked(apiClient.post).mockResolvedValue({ data: {} });
    render(<ResetPasswordScreen />);
    await user.type(screen.getByLabelText('Nouveau mot de passe'), 'NewPass1!');
    await user.type(screen.getByLabelText('Confirmer le mot de passe'), 'NewPass1!');
    await user.click(screen.getByRole('button', { name: /reinitialiser/i }));
    expect(await screen.findByText(/reinitialise avec succes/i)).toBeInTheDocument();
    expect(screen.getByText(/Se connecter/i)).toBeInTheDocument();
  });

  it('shows API error on failed reset', async () => {
    const user = userEvent.setup();
    vi.mocked(apiClient.post).mockRejectedValue({
      response: { data: { detail: 'Token expiré ou invalide' } },
    });
    render(<ResetPasswordScreen />);
    await user.type(screen.getByLabelText('Nouveau mot de passe'), 'NewPass1!');
    await user.type(screen.getByLabelText('Confirmer le mot de passe'), 'NewPass1!');
    await user.click(screen.getByRole('button', { name: /reinitialiser/i }));
    expect(await screen.findByText('Token expiré ou invalide')).toBeInTheDocument();
  });

  it('shows password mismatch error', async () => {
    const user = userEvent.setup();
    render(<ResetPasswordScreen />);
    await user.type(screen.getByLabelText('Nouveau mot de passe'), 'NewPass1!');
    await user.type(screen.getByLabelText('Confirmer le mot de passe'), 'Different1!');
    await user.click(screen.getByRole('button', { name: /reinitialiser/i }));
    expect(await screen.findByText(/ne correspondent pas/i)).toBeInTheDocument();
  });

  it('renders SchoolTrack copyright footer', () => {
    render(<ResetPasswordScreen />);
    expect(screen.getByText(/SchoolTrack.*EPHEC/i)).toBeInTheDocument();
  });
});
