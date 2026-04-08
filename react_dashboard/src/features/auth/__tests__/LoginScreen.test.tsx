import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '../../../test/test-utils';
import userEvent from '@testing-library/user-event';
import LoginScreen from '../screens/LoginScreen';
import { apiClient } from '@/api/axios';

vi.mock('@/api/axios', () => ({
  apiClient: { post: vi.fn() },
}));

vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return { ...actual, useParams: () => ({ schoolSlug: 'dev' }), useNavigate: () => vi.fn() };
});

beforeEach(() => vi.clearAllMocks());

describe('LoginScreen', () => {
  it('renders email and password fields', () => {
    render(<LoginScreen />);
    expect(screen.getByLabelText('Adresse Email')).toBeInTheDocument();
    expect(screen.getByLabelText('Mot de passe')).toBeInTheDocument();
  });

  it('renders login button', () => {
    render(<LoginScreen />);
    expect(screen.getByRole('button', { name: /se connecter/i })).toBeInTheDocument();
  });

  it('renders SchoolTrack title', () => {
    render(<LoginScreen />);
    expect(screen.getByText('SchoolTrack')).toBeInTheDocument();
    expect(screen.getByText('Dashboard Direction')).toBeInTheDocument();
  });

  it('renders forgot password link', () => {
    render(<LoginScreen />);
    expect(screen.getByText(/mot de passe oublie/i)).toBeInTheDocument();
  });

  it('shows toggle password visibility button', async () => {
    const user = userEvent.setup();
    render(<LoginScreen />);
    const toggleBtn = screen.getByLabelText(/afficher le mot de passe/i);
    expect(toggleBtn).toBeInTheDocument();
    await user.click(toggleBtn);
    expect(screen.getByLabelText(/masquer le mot de passe/i)).toBeInTheDocument();
  });

  it('shows error on failed login', async () => {
    const user = userEvent.setup();
    vi.mocked(apiClient.post).mockRejectedValue({
      response: { data: { detail: 'Identifiants invalides' } },
    });
    render(<LoginScreen />);
    await user.type(screen.getByLabelText('Adresse Email'), 'bad@test.be');
    await user.type(screen.getByLabelText('Mot de passe'), 'wrongpass');
    await user.click(screen.getByRole('button', { name: /se connecter/i }));
    expect(await screen.findByText('Identifiants invalides')).toBeInTheDocument();
  });

  it('shows 2FA form on 2FA_REQUIRED', async () => {
    const user = userEvent.setup();
    vi.mocked(apiClient.post).mockRejectedValue({
      response: { data: { detail: '2FA_REQUIRED' } },
    });
    render(<LoginScreen />);
    await user.type(screen.getByLabelText('Adresse Email'), 'admin@test.be');
    await user.type(screen.getByLabelText('Mot de passe'), 'Admin123!');
    await user.click(screen.getByRole('button', { name: /se connecter/i }));
    expect(await screen.findByLabelText(/Code 2FA/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /rifier/i })).toBeInTheDocument();
  });

  it('shows email 2FA description', async () => {
    const user = userEvent.setup();
    vi.mocked(apiClient.post).mockRejectedValue({
      response: { data: { detail: '2FA_REQUIRED_EMAIL' } },
    });
    render(<LoginScreen />);
    await user.type(screen.getByLabelText('Adresse Email'), 'admin@test.be');
    await user.type(screen.getByLabelText('Mot de passe'), 'Admin123!');
    await user.click(screen.getByRole('button', { name: /se connecter/i }));
    expect(await screen.findByText(/code de v.rification.*email/i)).toBeInTheDocument();
  });

  it('shows generic error when no detail', async () => {
    const user = userEvent.setup();
    vi.mocked(apiClient.post).mockRejectedValue({ response: { data: {} } });
    render(<LoginScreen />);
    await user.type(screen.getByLabelText('Adresse Email'), 'a@b.be');
    await user.type(screen.getByLabelText('Mot de passe'), 'pass');
    await user.click(screen.getByRole('button', { name: /se connecter/i }));
    expect(await screen.findByText(/erreur est survenue/i)).toBeInTheDocument();
  });
});
