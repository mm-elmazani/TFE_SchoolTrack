import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '../../../test/test-utils';
import userEvent from '@testing-library/user-event';
import ForgotPasswordScreen from '../screens/ForgotPasswordScreen';
import { apiClient } from '@/api/axios';

vi.mock('@/api/axios', () => ({
  apiClient: { post: vi.fn() },
}));

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return { ...actual, useParams: () => ({ schoolSlug: 'dev' }) };
});

beforeEach(() => vi.clearAllMocks());

describe('ForgotPasswordScreen', () => {
  it('renders email input', () => {
    render(<ForgotPasswordScreen />);
    expect(screen.getByLabelText(/email/i)).toBeInTheDocument();
  });

  it('renders submit button', () => {
    render(<ForgotPasswordScreen />);
    expect(screen.getByRole('button', { name: /envoyer/i })).toBeInTheDocument();
  });

  it('renders page title', () => {
    render(<ForgotPasswordScreen />);
    expect(screen.getByText('Mot de passe oublie')).toBeInTheDocument();
  });

  it('shows success after submit', async () => {
    const user = userEvent.setup();
    vi.mocked(apiClient.post).mockResolvedValue({ data: {} });
    render(<ForgotPasswordScreen />);
    await user.type(screen.getByLabelText(/email/i), 'test@ecole.be');
    await user.click(screen.getByRole('button', { name: /envoyer/i }));
    expect(await screen.findByText(/un lien de reinitialisation a ete envoye/i)).toBeInTheDocument();
    expect(screen.getByText(/Retour a la connexion/)).toBeInTheDocument();
  });

  it('shows error on failed submit', async () => {
    const user = userEvent.setup();
    vi.mocked(apiClient.post).mockRejectedValue({
      response: { data: { detail: 'Erreur serveur' } },
    });
    render(<ForgotPasswordScreen />);
    await user.type(screen.getByLabelText(/email/i), 'test@ecole.be');
    await user.click(screen.getByRole('button', { name: /envoyer/i }));
    expect(await screen.findByText('Erreur serveur')).toBeInTheDocument();
  });
});
